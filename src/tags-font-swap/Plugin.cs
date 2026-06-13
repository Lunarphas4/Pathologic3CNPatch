using System;
using System.Collections.Generic;
using System.Reflection;
using BepInEx;
using BepInEx.Logging;
using HarmonyLib;
using UnityEngine;

namespace Pathologic3CnTagsFontSwap
{
    // BepInEx plugin: forces NPC "cloud tag" floating text to render with NotoSansSC SDF
    // so CN characters become visible.
    //
    // Architecture (reverse-engineered from Scripts.dll, 2026-05-10):
    //   - The visible NPC floating text is rendered by Assets.Scripts.Game.Tags
    //     .TagsTextRenderingController (and its UGUI / UGUIV2 variants).
    //   - Each controller exposes TextSetuppers[] — an array of TextMeshProProjectedText
    //     DataSetupper / -UGUI MonoBehaviours.
    //   - Each setupper has a 'textComponent' field (TMP_Text) or 'TMProUGUI' field
    //     (TextMeshProUGUI). That field is the real TMP that renders the text.
    //   - TagsTextController (different class) also exists and has its own TextMeshPro[]
    //     TextSetuppers; we still hook it for safety, even though the v1 build of this
    //     plugin proved that hooking it alone doesn't fix floating tags.
    //   - TagsEntityController has a single 'textMesh' field — also covered.
    //
    // Why we don't change the underlying 278812 (Vollkorn-RegularWobbleUGUI) font:
    //   That font is shared with walls / pause menu / settings panel. Replacing its
    //   primary with a CJK font causes wobble shader to distort every CN char on those
    //   surfaces. By only swapping the font on these specific cloud-tag TMPs at
    //   runtime, walls and menus remain on Vollkorn (CJK via fallback, no wobble).
    //
    // Safety:
    //   - Runtime font swaps are limited to cloud/focus tags and the full-screen
    //     ThoughtController. Wall/mind-map 3D projected text keeps its original
    //     Vollkorn/fallback stack; forcing Noto there blurs Chinese on projected walls.
    //   - Pure reflection — no compile-time TMP type references.
    //   - All inner work wrapped in try/catch.
    //   - ReferenceEquals short-circuits when font already matches; cheap to call
    //     repeatedly from SetText hooks.

    [BepInPlugin(PluginGuid, PluginName, PluginVersion)]
    public sealed class Plugin : BaseUnityPlugin
    {
        public const string PluginGuid = "com.pathologic3.cn.tagsfontswap";
        public const string PluginName = "Pathologic3 CN Tags Font Swap";
        public const string PluginVersion = "0.8.10";

        private const string TargetFontName = "NotoSansSC-Regular SDF";
        private const string TagsActivateMethodName = "Assets.Scripts.Game.Tags.Controllers.ITagsComponentController.Activate";
        private const string TagsDeactivateMethodName = "Assets.Scripts.Game.Tags.Controllers.ITagsComponentController.Deactivate";
        private const int MaxSwapLogsPerType = 8;
        private const int MaxDeferredTagChildHygienePerFrame = 4;
        private const int MaxDeferredUiTagsGroupFontsPerFrame = 1;
        private const int MinUiTagsGroupFontRefreshFrames = 15;

        // Controller types whose Awake / SetText we'll hook.
        // For each: (typeName, fieldOnController, fieldOnSetupper)
        // - fieldOnController: array/list field that holds the setupper objects (or raw TMPs).
        // - fieldOnSetupper: name of the TMP field on each setupper. If null, the setupper IS
        //   the TMP itself (TextMeshPro / TextMeshProUGUI subclass).
        private static readonly ControllerSpec[] Controllers = new[]
        {
            // Real cloud-tag rendering controllers — these are the ones we believe drive
            // visible NPC floating text.
            new ControllerSpec("Assets.Scripts.Game.Tags.TagsTextRenderingController",
                "TextSetuppers", "textComponent"),
            new ControllerSpec("Assets.Scripts.Game.Tags.TagsTextRenderingControllerUGUI",
                "TextSetuppers", "TMProUGUI"),
            new ControllerSpec("Assets.Scripts.Game.Tags.TagsTextRenderingControllerUGUIV2",
                "TextSetuppers", "TMProUGUI"),

            // Single-TMP entity controller variant.
            new ControllerSpec("Assets.Scripts.Game.Tags.Controllers.TagsEntityController",
                "textMesh", null),

            // Older array-of-raw-TMPs controller (kept for safety; v1 of this plugin
            // already covered it).
            new ControllerSpec("Assets.Scripts.Game.Tags.Controllers.TagsTextController",
                "TextSetuppers", null),

            // Mind-palace 3D entity controllers (the dedicated mind-palace scene where
            // text fragments float on architectural surfaces). All expose a List<TextMeshPro>
            // textMeshPros field (defined on base or on MindMap3dEntityController itself).
            // With Vollkorn-primary + NotoSansSC fallback, CN chars there go to a fallback
            // sub-mesh that this controller's tween/positioning pipeline doesn't render —
            // same root cause as cloud tags.
            // Concrete subclasses of WallMindMap3dEntityControllerBase (abstract base — can't
            // patch directly, must target the concrete subclasses). Both inherit textMeshPros.
            // Hints controller (mind-palace hint overlay).

            // Full-screen black desk/books Mind Palace UI. This is separate from
            // wall/world projected mind-map controllers.
            new ControllerSpec("Assets.Scripts.UI.Dialogs.ThoughtController",
                "speech", null),
        };

        internal sealed class ControllerSpec
        {
            public readonly string TypeName;
            public readonly string ContainerField;
            public readonly string TmpFieldOnSetupper; // null if container field is already the TMP / TMP collection
            public ControllerSpec(string typeName, string containerField, string tmpFieldOnSetupper)
            {
                TypeName = typeName;
                ContainerField = containerField;
                TmpFieldOnSetupper = tmpFieldOnSetupper;
            }
        }

        internal static ManualLogSource Log;
        private static UnityEngine.Object cachedNotoFont;
        private static bool warnedNotFound;
        private static readonly Dictionary<string, int> swapLogsByType = new Dictionary<string, int>();
        private static int directWallTextLogs;
        private static int wallMindFallbackLogs;
        private static int localizationFallbackLogs;
        private static int wallMindDiagnosticLogs;
        private static int thoughtTextLogs;
        private static int childFontLogs;
        private static int inputIconLogs;
        private static int clearTextLogs;
        private static int inspectionLogs;
        private static int ammoNotificationLogs;
        private static readonly HashSet<int> tagRuntimeHygieneApplied = new HashSet<int>();
        private static readonly Dictionary<string, Type> typeCache = new Dictionary<string, Type>(StringComparer.Ordinal);
        private static readonly Dictionary<string, FieldInfo> fieldCache = new Dictionary<string, FieldInfo>(StringComparer.Ordinal);
        private static readonly Dictionary<string, PropertyInfo> propertyCache = new Dictionary<string, PropertyInfo>(StringComparer.Ordinal);
        private static readonly Queue<Component> deferredTagChildHygiene = new Queue<Component>();
        private static readonly HashSet<int> deferredTagChildHygieneQueued = new HashSet<int>();
        private static readonly Queue<Component> deferredUiTagsGroupFonts = new Queue<Component>();
        private static readonly HashSet<int> deferredUiTagsGroupFontsQueued = new HashSet<int>();
        private static readonly Dictionary<int, int> uiTagsGroupFontsLastFrame = new Dictionary<int, int>();
        private static readonly Dictionary<int, string> wallMindFallbackSignatures = new Dictionary<int, string>();

        private void Awake()
        {
            Log = Logger;
            try
            {
                var harmony = new Harmony(PluginGuid);
                harmony.PatchAll(typeof(Plugin).Assembly);
                Logger.LogInfo("TagsFontSwap v" + PluginVersion + " initialised; will hook " + Controllers.Length + " controller types.");
            }
            catch (Exception e)
            {
                Logger.LogError("TagsFontSwap PatchAll failed: " + e);
            }
        }

        private void Update()
        {
            for (var i = 0; i < MaxDeferredTagChildHygienePerFrame; i++)
            {
                var component = DequeueDeferredTagChildHygiene();
                if (component == null)
                {
                    break;
                }

                ApplyFontsInChildren(component, "Tag controller deferred");
                HideInputActionIcons(component);
            }

            for (var i = 0; i < MaxDeferredUiTagsGroupFontsPerFrame; i++)
            {
                var component = DequeueDeferredUiTagsGroupFonts();
                if (component == null)
                {
                    break;
                }

                ApplyFontsInChildren(component, "UITagsGroup deferred");
                uiTagsGroupFontsLastFrame[component.GetInstanceID()] = Time.frameCount;
            }
        }

        internal static UnityEngine.Object GetNotoFont()
        {
            if (cachedNotoFont != null)
            {
                return cachedNotoFont;
            }

            try
            {
                var fontType = AccessTools.TypeByName("TMPro.TMP_FontAsset");
                if (fontType == null)
                {
                    return null;
                }

                var loaded = Resources.FindObjectsOfTypeAll(fontType);
                if (loaded == null)
                {
                    return null;
                }

                for (var i = 0; i < loaded.Length; i++)
                {
                    var candidate = loaded[i];
                    if (candidate == null)
                    {
                        continue;
                    }
                    if (candidate.name == TargetFontName)
                    {
                        cachedNotoFont = candidate;
                        if (Log != null)
                        {
                            Log.LogInfo("Cached NotoSansSC font asset (instance id " + candidate.GetInstanceID() + ")");
                        }
                        return cachedNotoFont;
                    }
                }

                if (!warnedNotFound && Log != null)
                {
                    warnedNotFound = true;
                    Log.LogWarning("NotoSansSC SDF not yet loaded; will retry on next call.");
                }
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogError("GetNotoFont failed: " + e);
                }
            }
            return null;
        }

        private static Type GetCachedType(string typeName)
        {
            if (string.IsNullOrEmpty(typeName))
            {
                return null;
            }

            Type cached;
            if (typeCache.TryGetValue(typeName, out cached))
            {
                return cached;
            }

            cached = AccessTools.TypeByName(typeName);
            typeCache[typeName] = cached;
            return cached;
        }

        private static FieldInfo GetCachedField(Type type, string fieldName)
        {
            if (type == null || string.IsNullOrEmpty(fieldName))
            {
                return null;
            }

            var key = type.FullName + "::field::" + fieldName;
            FieldInfo cached;
            if (fieldCache.TryGetValue(key, out cached))
            {
                return cached;
            }

            cached = AccessTools.Field(type, fieldName);
            fieldCache[key] = cached;
            return cached;
        }

        private static PropertyInfo GetCachedProperty(Type type, string propertyName)
        {
            if (type == null || string.IsNullOrEmpty(propertyName))
            {
                return null;
            }

            var key = type.FullName + "::prop::" + propertyName;
            PropertyInfo cached;
            if (propertyCache.TryGetValue(key, out cached))
            {
                return cached;
            }

            cached = AccessTools.Property(type, propertyName);
            propertyCache[key] = cached;
            return cached;
        }

        // Try to set the 'font' property on a TMP_Text/TextMeshPro/TextMeshProUGUI instance.
        // Returns true if the font was actually changed.
        private static bool TrySetFont(object tmp, UnityEngine.Object noto)
        {
            if (tmp == null || noto == null)
            {
                return false;
            }
            var fontProp = GetCachedProperty(tmp.GetType(), "font");
            if (fontProp == null || !fontProp.CanWrite)
            {
                return false;
            }

            object current;
            try
            {
                current = fontProp.GetValue(tmp, null);
            }
            catch
            {
                current = null;
            }

            if (ReferenceEquals(current, noto))
            {
                return false;
            }

            try
            {
                fontProp.SetValue(tmp, noto, null);
                return true;
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogWarning("font set failed: " + e.Message);
                }
                return false;
            }
        }

        private static bool TrySetText(object tmp, string text, bool forceMeshUpdate)
        {
            if (tmp == null)
            {
                return false;
            }

            try
            {
                var textProp = GetCachedProperty(tmp.GetType(), "text");
                if (textProp == null || !textProp.CanWrite)
                {
                    return false;
                }
                textProp.SetValue(tmp, text ?? string.Empty, null);

                if (forceMeshUpdate)
                {
                    // Only use synchronous TMP mesh rebuilds on narrow, explicit paths.
                    // Bulk clear/populate hooks run during focus/dialog/map transitions and
                    // must let TMP refresh naturally on the next frame to avoid long stalls.
                    const BindingFlags flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
                    var update = tmp.GetType().GetMethod("ForceMeshUpdate", flags, null, new Type[0], null);
                    if (update != null)
                    {
                        update.Invoke(tmp, null);
                    }
                    else
                    {
                        update = tmp.GetType().GetMethod("ForceMeshUpdate", flags, null, new[] { typeof(bool), typeof(bool) }, null);
                        if (update != null)
                        {
                            update.Invoke(tmp, new object[] { false, false });
                        }
                    }
                }
                return true;
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogWarning("text set failed: " + e.Message);
                }
                return false;
            }
        }

        private static string Preview(string text, int maxLen)
        {
            var preview = text ?? string.Empty;
            preview = preview.Replace("\r", "\\r").Replace("\n", "\\n");
            if (preview.Length > maxLen)
            {
                preview = preview.Substring(0, maxLen) + "...";
            }
            return preview;
        }

        private static string GetFieldString(object instance, string fieldName)
        {
            if (instance == null)
            {
                return "<null>";
            }
            try
            {
                var field = AccessTools.Field(instance.GetType(), fieldName);
                if (field == null)
                {
                    return "<missing>";
                }
                var value = field.GetValue(instance);
                return value == null ? "<null>" : value.ToString();
            }
            catch (Exception e)
            {
                return "<error:" + e.GetType().Name + ">";
            }
        }

        private static int GetListCount(object instance, string fieldName)
        {
            try
            {
                var field = AccessTools.Field(instance.GetType(), fieldName);
                if (field == null)
                {
                    return -1;
                }
                var list = field.GetValue(instance) as System.Collections.ICollection;
                return list == null ? -1 : list.Count;
            }
            catch
            {
                return -1;
            }
        }

        private static string GetComponentPath(object instance)
        {
            var component = instance as Component;
            if (component == null)
            {
                return "<not-component>";
            }
            try
            {
                var names = new List<string>();
                var current = component.transform;
                var guard = 0;
                while (current != null && guard < 32)
                {
                    names.Insert(0, current.name);
                    current = current.parent;
                    guard++;
                }
                return string.Join("/", names.ToArray());
            }
            catch (Exception e)
            {
                return "<path-error:" + e.GetType().Name + ">";
            }
        }

        private static void LogWallMindDiagnostic(object controller)
        {
            if (Log == null || controller == null || wallMindDiagnosticLogs >= 8)
            {
                return;
            }
            wallMindDiagnosticLogs++;

            try
            {
                var raw = new List<string>();
                var enumerate = AccessTools.Method(controller.GetType(), "EnumerateMindModels");
                if (enumerate != null)
                {
                    var enumerable = enumerate.Invoke(controller, null) as System.Collections.IEnumerable;
                    if (enumerable != null)
                    {
                        foreach (var item in enumerable)
                        {
                            raw.Add(item == null ? "<null>" : item.ToString());
                            if (raw.Count >= 8)
                            {
                                break;
                            }
                        }
                    }
                }

                var rawText = raw.Count == 0 ? "<none>" : string.Join(" | ", raw.ConvertAll(s => Preview(s, 90)).ToArray());
                Log.LogInfo(
                    "WallMindMap diag type=" + controller.GetType().FullName +
                    " path=\"" + GetComponentPath(controller) + "\"" +
                    " useTimeMindMap=" + GetFieldString(controller, "useTimeMindMap") +
                    " useExportData=" + GetFieldString(controller, "useExportData") +
                    " useSelectedDay=" + GetFieldString(controller, "useSelectedDay") +
                    " selectedDay=" + GetFieldString(controller, "selectedDay") +
                    " tmpCount=" + GetListCount(controller, "textMeshPros") +
                    " rawCountLogged=" + raw.Count +
                    " raw=\"" + rawText + "\"");
            }
            catch (Exception e)
            {
                Log.LogWarning("WallMindMap diagnostic failed: " + e.Message);
            }
        }

        private static bool IsLocalizationMiss(string tag, string result)
        {
            return string.IsNullOrEmpty(result) || result == tag;
        }

        private static bool TryArchiveMindsFallback(object localizationService, string tag, ref string result)
        {
            if (localizationService == null || string.IsNullOrEmpty(tag) || !tag.StartsWith("{Minds.", StringComparison.Ordinal))
            {
                return false;
            }
            if (!IsLocalizationMiss(tag, result))
            {
                return false;
            }

            var getText = AccessTools.Method(localizationService.GetType(), "GetText", new[] { typeof(string) });
            if (getText == null)
            {
                return false;
            }

            var alternates = new[]
            {
                "{ArchiveMinds." + tag.Substring("{Minds.".Length),
                "{ArchiveMinds.Old." + tag.Substring("{Minds.".Length)
            };

            for (var i = 0; i < alternates.Length; i++)
            {
                var alt = alternates[i];
                string altResult = null;
                try
                {
                    altResult = getText.Invoke(localizationService, new object[] { alt }) as string;
                }
                catch (Exception e)
                {
                    if (Log != null && localizationFallbackLogs < 20)
                    {
                        localizationFallbackLogs++;
                        Log.LogWarning("ArchiveMinds fallback invoke failed for " + Preview(tag, 120) + ": " + e.Message);
                    }
                    continue;
                }

                if (!IsLocalizationMiss(alt, altResult))
                {
                    result = altResult;
                    if (Log != null && localizationFallbackLogs < 20)
                    {
                        localizationFallbackLogs++;
                        Log.LogInfo("ArchiveMinds fallback " + Preview(tag, 120) + " -> " + Preview(alt, 120) + " len=" + altResult.Length);
                    }
                    return true;
                }
            }

            return false;
        }

        private static object GetServiceInstance(string serviceTypeName)
        {
            try
            {
                var serviceType = AccessTools.TypeByName(serviceTypeName);
                var serviceInstanceOpen = AccessTools.TypeByName("Core.Services.ServiceInstance`1");
                if (serviceType == null || serviceInstanceOpen == null)
                {
                    return null;
                }
                var serviceInstanceType = serviceInstanceOpen.MakeGenericType(serviceType);
                var instanceProp = AccessTools.Property(serviceInstanceType, "Instance");
                return instanceProp == null ? null : instanceProp.GetValue(null, null);
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogWarning("GetServiceInstance(" + serviceTypeName + ") failed: " + e.Message);
                }
                return null;
            }
        }

        private static MethodInfo FindGenericNoArgMethod(Type type, string name)
        {
            if (type == null)
            {
                return null;
            }
            const BindingFlags flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
            while (type != null)
            {
                var methods = type.GetMethods(flags);
                for (var i = 0; i < methods.Length; i++)
                {
                    var method = methods[i];
                    if (method.Name == name && method.IsGenericMethodDefinition && method.GetParameters().Length == 0)
                    {
                        return method;
                    }
                }
                type = type.BaseType;
            }
            return null;
        }

        private static string LocalizeText(string tag)
        {
            if (string.IsNullOrEmpty(tag))
            {
                return string.Empty;
            }
            try
            {
                var localization = GetServiceInstance("Localizations.LocalizationService");
                if (localization == null)
                {
                    return tag;
                }
                var getText = AccessTools.Method(localization.GetType(), "GetText", new[] { typeof(string) });
                if (getText == null)
                {
                    return tag;
                }
                var localized = getText.Invoke(localization, new object[] { tag }) as string;
                return localized ?? string.Empty;
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogWarning("LocalizeText failed for " + Preview(tag, 80) + ": " + e.Message);
                }
                return tag;
            }
        }

        private static object GetModelDefinition(object model)
        {
            if (model == null)
            {
                return null;
            }
            try
            {
                var prop = AccessTools.Property(model.GetType(), "Definition");
                return prop == null ? null : prop.GetValue(model, null);
            }
            catch
            {
                return null;
            }
        }

        private static bool GetBoolProperty(object instance, string name)
        {
            try
            {
                var prop = AccessTools.Property(instance.GetType(), name);
                if (prop == null)
                {
                    return false;
                }
                var value = prop.GetValue(instance, null);
                return value is bool && (bool)value;
            }
            catch
            {
                return false;
            }
        }

        private static object GetFieldValue(object instance, string name)
        {
            try
            {
                var field = AccessTools.Field(instance.GetType(), name);
                return field == null ? null : field.GetValue(instance);
            }
            catch
            {
                return null;
            }
        }

        private static bool MarkRuntimeObject(HashSet<int> seen, object instance)
        {
            if (instance == null)
            {
                return false;
            }

            var unityObject = instance as UnityEngine.Object;
            var id = unityObject == null ? instance.GetHashCode() : unityObject.GetInstanceID();
            lock (seen)
            {
                if (seen.Contains(id))
                {
                    return false;
                }
                seen.Add(id);
                return true;
            }
        }

        private static int GetRuntimeId(object instance)
        {
            var unityObject = instance as UnityEngine.Object;
            return unityObject == null ? instance.GetHashCode() : unityObject.GetInstanceID();
        }

        private static void EnqueueDeferredTagChildHygiene(object instance)
        {
            var component = instance as Component;
            if (component == null)
            {
                return;
            }

            var id = component.GetInstanceID();
            lock (deferredTagChildHygiene)
            {
                if (deferredTagChildHygieneQueued.Contains(id))
                {
                    return;
                }
                deferredTagChildHygieneQueued.Add(id);
                deferredTagChildHygiene.Enqueue(component);
            }
        }

        private static Component DequeueDeferredTagChildHygiene()
        {
            lock (deferredTagChildHygiene)
            {
                while (deferredTagChildHygiene.Count > 0)
                {
                    var component = deferredTagChildHygiene.Dequeue();
                    if (component != null)
                    {
                        return component;
                    }
                }
            }
            return null;
        }

        private static void EnqueueDeferredUiTagsGroupFonts(object instance)
        {
            var component = instance as Component;
            if (component == null)
            {
                return;
            }

            var id = component.GetInstanceID();
            lock (deferredUiTagsGroupFonts)
            {
                if (deferredUiTagsGroupFontsQueued.Contains(id))
                {
                    return;
                }

                int lastFrame;
                if (uiTagsGroupFontsLastFrame.TryGetValue(id, out lastFrame) &&
                    Time.frameCount - lastFrame < MinUiTagsGroupFontRefreshFrames)
                {
                    return;
                }

                deferredUiTagsGroupFontsQueued.Add(id);
                deferredUiTagsGroupFonts.Enqueue(component);
            }
        }

        private static Component DequeueDeferredUiTagsGroupFonts()
        {
            lock (deferredUiTagsGroupFonts)
            {
                while (deferredUiTagsGroupFonts.Count > 0)
                {
                    var component = deferredUiTagsGroupFonts.Dequeue();
                    if (component != null)
                    {
                        deferredUiTagsGroupFontsQueued.Remove(component.GetInstanceID());
                        return component;
                    }
                }
            }
            return null;
        }

        private static bool IsEnumInt(object value, int expected)
        {
            try
            {
                return value != null && Convert.ToInt32(value) == expected;
            }
            catch
            {
                return false;
            }
        }

        private static bool IsFallbackWallTimeMindMap(object controller)
        {
            if (controller == null || controller.GetType().FullName != "Assets.Scripts.Game.Tags.Controllers.WallMindMap3dEntityController")
            {
                return false;
            }
            if (GetFieldString(controller, "useTimeMindMap") != "True")
            {
                return false;
            }
            if (GetFieldString(controller, "useExportData") == "True")
            {
                return false;
            }
            var path = GetComponentPath(controller);
            return path.IndexOf("MM_Tags/Time MindMap", StringComparison.OrdinalIgnoreCase) >= 0 ||
                path.EndsWith("/Time MindMap", StringComparison.OrdinalIgnoreCase);
        }

        private static string BuildWallMindFallbackSignature(object controller)
        {
            return GetComponentPath(controller) +
                "|selectedDay=" + GetFieldString(controller, "selectedDay") +
                "|useSelectedDay=" + GetFieldString(controller, "useSelectedDay") +
                "|tmpCount=" + GetListCount(controller, "textMeshPros");
        }

        private static bool TryPopulateWallMindFallback(object controller)
        {
            if (!IsFallbackWallTimeMindMap(controller))
            {
                return false;
            }

            try
            {
                var id = GetRuntimeId(controller);
                var signature = BuildWallMindFallbackSignature(controller);
                lock (wallMindFallbackSignatures)
                {
                    string cachedSignature;
                    if (wallMindFallbackSignatures.TryGetValue(id, out cachedSignature) &&
                        cachedSignature == signature)
                    {
                        return true;
                    }
                }

                var modelService = GetServiceInstance("Assets.Scripts.Game.Quests.Models.MindModelService");
                var mindModelType = AccessTools.TypeByName("Assets.Scripts.Game.Quests.Models.MindModel");
                if (modelService == null || mindModelType == null)
                {
                    return false;
                }

                var getModelsOpen = FindGenericNoArgMethod(modelService.GetType(), "GetModels");
                if (getModelsOpen == null)
                {
                    return false;
                }

                var getModels = getModelsOpen.MakeGenericMethod(mindModelType);
                var models = getModels.Invoke(modelService, null) as System.Collections.IEnumerable;
                if (models == null)
                {
                    return false;
                }

                var hasEnabledChilds = AccessTools.Method(controller.GetType(), "HasEnabledChilds");
                var getModelText = AccessTools.Method(controller.GetType(), "GetModelText");
                var max = GetListCount(controller, "textMeshPros");
                var count = 0;
                var seen = new Dictionary<string, bool>();

                foreach (var model in models)
                {
                    if (model == null)
                    {
                        continue;
                    }
                    if (!GetBoolProperty(model, "Enable"))
                    {
                        continue;
                    }

                    var definition = GetModelDefinition(model);
                    if (definition == null)
                    {
                        continue;
                    }

                    // MindMapEnum.TimeMap == 1; MindType 2/3 are excluded by the original route.
                    if (!IsEnumInt(GetFieldValue(definition, "MindMap"), 1))
                    {
                        continue;
                    }
                    if (IsEnumInt(GetFieldValue(definition, "MindType"), 2) || IsEnumInt(GetFieldValue(definition, "MindType"), 3))
                    {
                        continue;
                    }
                    if (hasEnabledChilds != null && (bool)hasEnabledChilds.Invoke(controller, new object[] { model }))
                    {
                        continue;
                    }

                    string key = null;
                    if (getModelText != null)
                    {
                        key = getModelText.Invoke(controller, new object[] { model }) as string;
                    }
                    if (string.IsNullOrEmpty(key))
                    {
                        key = GetFieldValue(definition, "Description") as string;
                    }

                    var localized = LocalizeText(key);
                    if (string.IsNullOrWhiteSpace(localized) || seen.ContainsKey(localized))
                    {
                        continue;
                    }

                    seen[localized] = true;
                    SetListTextDirect(controller, "textMeshPros", count, localized, true);
                    count++;
                    if (max > 0 && count >= max)
                    {
                        break;
                    }
                }

                if (count <= 0)
                {
                    return false;
                }

                for (var i = count; i < max; i++)
                {
                    SetListTextDirect(controller, "textMeshPros", i, string.Empty, false);
                }

                lock (wallMindFallbackSignatures)
                {
                    wallMindFallbackSignatures[id] = signature;
                }

                if (Log != null && wallMindFallbackLogs < 8)
                {
                    wallMindFallbackLogs++;
                    Log.LogInfo("WallMindMap fallback populated " + count + " TimeMap texts for " + GetComponentPath(controller));
                }
                return true;
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogError("TryPopulateWallMindFallback failed: " + e);
                }
                return false;
            }
        }

        private static bool SetListTextDirect(object controller, string listFieldName, int index, string text, bool logPreview)
        {
            if (controller == null || index < 0)
            {
                return true;
            }

            try
            {
                var listField = GetCachedField(controller.GetType(), listFieldName);
                if (listField == null)
                {
                    return true;
                }
                var list = listField.GetValue(controller) as System.Collections.IList;
                if (list == null || index >= list.Count)
                {
                    return false;
                }

                var tmp = list[index];
                TrySetText(tmp, text, false);

                if (logPreview && Log != null && directWallTextLogs < 12)
                {
                    directWallTextLogs++;
                    Log.LogInfo(controller.GetType().FullName + " direct SetScreenText[" + index + "] len=" + (text == null ? 0 : text.Length) + " text=\"" + Preview(text, 80) + "\"");
                }
                return false;
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogError("SetListTextDirect failed: " + e);
                }
                return true;
            }
        }

        // Apply font swap to a controller instance per its spec.
        internal static int ForceFontFromSpec(object controller, ControllerSpec spec)
        {
            if (controller == null || spec == null)
            {
                return 0;
            }

            try
            {
                var instType = controller.GetType();
                var containerField = GetCachedField(instType, spec.ContainerField);
                if (containerField == null)
                {
                    return 0;
                }
                var containerVal = containerField.GetValue(controller);
                if (containerVal == null)
                {
                    return 0;
                }

                var noto = GetNotoFont();
                if (noto == null)
                {
                    return 0;
                }

                int swapped = 0;

                // Single TMP field (containerField is itself a TMP_Text reference).
                if (spec.TmpFieldOnSetupper == null && !(containerVal is Array) && !(containerVal is System.Collections.IEnumerable))
                {
                    if (TrySetFont(containerVal, noto))
                    {
                        swapped++;
                    }
                    return swapped;
                }
                // Note: when TmpFieldOnSetupper == null AND containerVal IS enumerable (Array/List of raw TMPs),
                // we fall through to the iterating branch below, which treats each element as the TMP itself.

                // Array-of-TMP (TextMeshPro[] case): containerField holds an Array of TMPs directly.
                // Array-of-setupper: containerField holds an Array of MonoBehaviour wrappers; we need
                // to descend into spec.TmpFieldOnSetupper on each.
                System.Collections.IEnumerable iter = containerVal as System.Collections.IEnumerable;
                if (iter == null)
                {
                    return 0;
                }

                foreach (var element in iter)
                {
                    if (element == null)
                    {
                        continue;
                    }

                    object tmp;
                    if (spec.TmpFieldOnSetupper == null)
                    {
                        // element is itself the TMP.
                        tmp = element;
                    }
                    else
                    {
                        var f = GetCachedField(element.GetType(), spec.TmpFieldOnSetupper);
                        if (f == null)
                        {
                            continue;
                        }
                        tmp = f.GetValue(element);
                    }

                    if (TrySetFont(tmp, noto))
                    {
                        swapped++;
                    }
                }

                return swapped;
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogError("ForceFontFromSpec(" + spec.TypeName + ") failed: " + e);
                }
                return 0;
            }
        }

        internal static void Apply(object controller)
        {
            if (controller == null)
            {
                return;
            }
            var typeName = controller.GetType().FullName;
            for (var i = 0; i < Controllers.Length; i++)
            {
                if (Controllers[i].TypeName == typeName)
                {
                    var swapped = ForceFontFromSpec(controller, Controllers[i]);
                    if (swapped > 0 && Log != null && ShouldLogSwap(typeName))
                    {
                        Log.LogInfo(typeName + " swapped " + swapped + " TMP -> NotoSansSC");
                    }
                    return;
                }
            }
        }

        private static int ApplyFontsInChildren(object root, string reason)
        {
            var component = root as Component;
            if (component == null)
            {
                return 0;
            }

            try
            {
                var tmpType = GetCachedType("TMPro.TMP_Text");
                var noto = GetNotoFont();
                if (tmpType == null || noto == null)
                {
                    return 0;
                }

                var tmps = component.GetComponentsInChildren(tmpType, true);
                var swapped = 0;
                for (var i = 0; i < tmps.Length; i++)
                {
                    if (TrySetFont(tmps[i], noto))
                    {
                        swapped++;
                    }
                }

                if (swapped > 0 && Log != null && childFontLogs < 24)
                {
                    childFontLogs++;
                    Log.LogInfo(reason + " child TMP font swap count=" + swapped + " path=\"" + GetComponentPath(component) + "\"");
                }
                return swapped;
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogWarning("ApplyFontsInChildren(" + reason + ") failed: " + e.Message);
                }
                return 0;
            }
        }

        private static int ClearTmpTextChildren(object root, string reason)
        {
            var component = root as Component;
            if (component == null)
            {
                return 0;
            }

            try
            {
                var tmpType = GetCachedType("TMPro.TMP_Text");
                if (tmpType == null)
                {
                    return 0;
                }

                var tmps = component.GetComponentsInChildren(tmpType, true);
                var cleared = 0;
                for (var i = 0; i < tmps.Length; i++)
                {
                    if (TrySetText(tmps[i], string.Empty, false))
                    {
                        cleared++;
                    }
                }

                if (cleared > 0 && Log != null && clearTextLogs < 16)
                {
                    clearTextLogs++;
                    Log.LogInfo(reason + " cleared child TMP count=" + cleared + " path=\"" + GetComponentPath(component) + "\"");
                }
                return cleared;
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogWarning("ClearTmpTextChildren(" + reason + ") failed: " + e.Message);
                }
                return 0;
            }
        }

        private static int HideInputActionIcons(object root)
        {
            var component = root as Component;
            if (component == null)
            {
                return 0;
            }

            try
            {
                var iconType = GetCachedType("Game.InputActions.InputActionIcon");
                if (iconType == null)
                {
                    return 0;
                }

                var icons = component.GetComponentsInChildren(iconType, true);
                var hidden = 0;
                for (var i = 0; i < icons.Length; i++)
                {
                    var icon = icons[i];
                    if (icon == null)
                    {
                        continue;
                    }

                    var buttonName = GetFieldValue(icon, "buttonName");
                    if (TrySetText(buttonName, string.Empty, false))
                    {
                        hidden++;
                    }

                    var iconComponent = icon as Component;
                    if (iconComponent != null && iconComponent.gameObject != null && iconComponent.gameObject.activeSelf)
                    {
                        iconComponent.gameObject.SetActive(false);
                        hidden++;
                    }
                }

                if (hidden > 0 && Log != null && inputIconLogs < 24)
                {
                    inputIconLogs++;
                    Log.LogInfo("Hidden input action icons count=" + hidden + " path=\"" + GetComponentPath(component) + "\"");
                }
                return hidden;
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogWarning("HideInputActionIcons failed: " + e.Message);
                }
                return 0;
            }
        }

        private static void ApplyTagRuntimeHygiene(object controller)
        {
            if (IsProjectedMindMapController(controller))
            {
                return;
            }

            if (GetNotoFont() == null)
            {
                return;
            }

            Apply(controller);
            if (!MarkRuntimeObject(tagRuntimeHygieneApplied, controller))
            {
                return;
            }
            EnqueueDeferredTagChildHygiene(controller);
        }

        private static void ClearTagRuntimeText(object controller)
        {
            // Let the game's own deactivate/clear logic handle tag lifetime.
            // Our extra recursive TMP clearing caused visible flashes and stalls
            // when focus tags were released or rebuilt after area travel.
        }

        private static bool IsProjectedMindMapController(object controller)
        {
            if (controller == null)
            {
                return false;
            }

            var typeName = controller.GetType().FullName;
            if (string.IsNullOrEmpty(typeName))
            {
                return false;
            }

            return typeName.IndexOf("MindMap3d", StringComparison.OrdinalIgnoreCase) >= 0 ||
                typeName.IndexOf("WallMindMap3d", StringComparison.OrdinalIgnoreCase) >= 0 ||
                typeName.IndexOf("WeatherMindMap3d", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        private static void ApplyUITagsGroup(object group)
        {
            if (group == null)
            {
                return;
            }

            try
            {
                var noto = GetNotoFont();
                var tags = GetFieldValue(group, "Tags") as System.Collections.IEnumerable;
                var swapped = 0;
                if (noto != null && tags != null)
                {
                    foreach (var tag in tags)
                    {
                        if (TrySetFont(tag, noto))
                        {
                            swapped++;
                        }
                    }
                }
                EnqueueDeferredUiTagsGroupFonts(group);
                if (swapped > 0 && Log != null && inspectionLogs < 16)
                {
                    inspectionLogs++;
                    Log.LogInfo("UITagsGroup swapped TMP count=" + swapped + " path=\"" + GetComponentPath(group) + "\"");
                }
            }
            catch (Exception e)
            {
                if (Log != null)
                {
                    Log.LogWarning("ApplyUITagsGroup failed: " + e.Message);
                }
            }
        }

        private static void ApplyInspectionTagsControl(object control)
        {
            if (control == null)
            {
                return;
            }

            ApplyFontsInChildren(control, "InspectionTagsControl");
            var group = GetFieldValue(control, "tagsGroup");
            ApplyUITagsGroup(group);
        }

        private static void ApplyThoughtController(object controller)
        {
            if (GetNotoFont() == null)
            {
                return;
            }

            Apply(controller);
        }

        private static void ApplyBubyldaAmmoNotificationController(object controller)
        {
            if (controller == null || GetNotoFont() == null)
            {
                return;
            }

            var noto = GetNotoFont();
            var swapped = 0;
            var text = GetFieldValue(controller, "text");
            if (TrySetFont(text, noto))
            {
                swapped++;
            }
            swapped += ApplyFontsInChildren(controller, "Bubylda ammo notification");

            if (swapped > 0 && Log != null && ammoNotificationLogs < 8)
            {
                ammoNotificationLogs++;
                Log.LogInfo("BubyldaAmmoNotificationController swapped TMP count=" + swapped + " path=\"" + GetComponentPath(controller) + "\"");
            }
        }

        private static void LogThoughtText(string text)
        {
            if (Log == null || thoughtTextLogs >= 16)
            {
                return;
            }
            thoughtTextLogs++;
            Log.LogInfo("ThoughtController SetText len=" + (text == null ? 0 : text.Length) + " text=\"" + Preview(text, 80) + "\"");
        }

        private static bool ShouldLogSwap(string typeName)
        {
            int count;
            if (swapLogsByType.TryGetValue(typeName, out count) && count >= MaxSwapLogsPerType)
            {
                return false;
            }
            swapLogsByType[typeName] = count + 1;
            return true;
        }

        private static MethodBase FindMethodByName(string typeName, string methodName)
        {
            var t = AccessTools.TypeByName(typeName);
            if (t == null)
            {
                return null;
            }

            const BindingFlags flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static;
            while (t != null)
            {
                var methods = t.GetMethods(flags);
                for (var i = 0; i < methods.Length; i++)
                {
                    if (methods[i].Name == methodName)
                    {
                        return methods[i];
                    }
                }
                t = t.BaseType;
            }
            return null;
        }

        private static MethodBase FindDeclaredMethod(string typeName, string methodName, Type[] parameters)
        {
            var t = AccessTools.TypeByName(typeName);
            if (t == null)
            {
                return null;
            }

            const BindingFlags flags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly;
            return parameters == null ? AccessTools.Method(t, methodName, null, null) : t.GetMethod(methodName, flags, null, parameters, null);
        }

        // ---- Patches ----

        [HarmonyPatch]
        private static class HookComputeUpdate_BuildLabelDrawer
        {
            private static MethodBase TargetMethod()
            {
                return FindMethodByName(
                    "Assets.Scripts.Game.DevMenu.Widgets.BuildLabelDrawer",
                    "UpdateServices.IUpdatable.ComputeUpdate");
            }

            private static bool Prefix()
            {
                return false;
            }
        }

        [HarmonyPatch]
        private static class HookGetText_LocalizationService
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Localizations.LocalizationService");
                return t == null ? null : AccessTools.Method(t, "GetText", new[] { typeof(string) });
            }
            private static void Postfix(object __instance, string tag, ref string __result)
            {
                TryArchiveMindsFallback(__instance, tag, ref __result);
            }
        }

        [HarmonyPatch]
        private static class HookAddTagController_TagsService
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.TagsService");
                return t == null ? null : AccessTools.Method(t, "AddTagController");
            }
            private static void Postfix(object tagsEntityController) { ApplyTagRuntimeHygiene(tagsEntityController); }
        }

        [HarmonyPatch]
        private static class HookAwake_TagsTextRenderingController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.TagsTextRenderingController");
                return t == null ? null : AccessTools.Method(t, "Awake");
            }
            private static void Postfix(object __instance) { ApplyTagRuntimeHygiene(__instance); }
        }

        [HarmonyPatch]
        private static class HookSetText_TagsTextRenderingController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.TagsTextRenderingController");
                return t == null ? null : AccessTools.Method(t, "SetText");
            }
            private static void Prefix(object __instance) { ApplyTagRuntimeHygiene(__instance); }
        }

        [HarmonyPatch]
        private static class HookAwake_TagsTextRenderingControllerUGUI
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.TagsTextRenderingControllerUGUI");
                return t == null ? null : AccessTools.Method(t, "Awake");
            }
            private static void Postfix(object __instance) { ApplyTagRuntimeHygiene(__instance); }
        }

        [HarmonyPatch]
        private static class HookSetText_TagsTextRenderingControllerUGUI
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.TagsTextRenderingControllerUGUI");
                return t == null ? null : AccessTools.Method(t, "SetText");
            }
            private static void Prefix(object __instance) { ApplyTagRuntimeHygiene(__instance); }
        }

        [HarmonyPatch]
        private static class HookAwake_TagsTextRenderingControllerUGUIV2
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.TagsTextRenderingControllerUGUIV2");
                return t == null ? null : AccessTools.Method(t, "Awake");
            }
            private static void Postfix(object __instance) { ApplyTagRuntimeHygiene(__instance); }
        }

        [HarmonyPatch]
        private static class HookSetText_TagsTextRenderingControllerUGUIV2
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.TagsTextRenderingControllerUGUIV2");
                return t == null ? null : AccessTools.Method(t, "SetText");
            }
            private static void Prefix(object __instance) { ApplyTagRuntimeHygiene(__instance); }
        }

        [HarmonyPatch]
        private static class HookSyncText_TagsEntityController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.TagsEntityController");
                return t == null ? null : AccessTools.Method(t, "SyncText");
            }
            private static void Prefix(object __instance) { ApplyTagRuntimeHygiene(__instance); }
        }

        [HarmonyPatch]
        private static class HookAwake_TagsTextController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.TagsTextController");
                return t == null ? null : AccessTools.Method(t, "Awake");
            }
            private static void Postfix(object __instance) { ApplyTagRuntimeHygiene(__instance); }
        }

        [HarmonyPatch]
        private static class HookSetText_TagsTextController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.TagsTextController");
                return t == null ? null : AccessTools.Method(t, "SetText", new[] { typeof(int), typeof(float), typeof(string) });
            }
            private static void Prefix(object __instance) { ApplyTagRuntimeHygiene(__instance); }
        }

        [HarmonyPatch]
        private static class HookClearText_TagsTextController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.TagsTextController");
                return t == null ? null : AccessTools.Method(t, "ClearText", new[] { typeof(float), typeof(float) });
            }
            private static void Postfix(object __instance) { ClearTagRuntimeText(__instance); }
        }

        [HarmonyPatch]
        private static class HookDeactivate_TagControllers
        {
            private static IEnumerable<MethodBase> TargetMethods()
            {
                var typeNames = new[]
                {
                    "Assets.Scripts.Game.Tags.TagsTextRenderingController",
                    "Assets.Scripts.Game.Tags.TagsTextRenderingControllerUGUI",
                    "Assets.Scripts.Game.Tags.TagsTextRenderingControllerUGUIV2",
                    "Assets.Scripts.Game.Tags.Controllers.TagsEntityController",
                    "Assets.Scripts.Game.Tags.Controllers.TagsTextController",
                };
                for (var i = 0; i < typeNames.Length; i++)
                {
                    var method = FindMethodByName(typeNames[i], TagsDeactivateMethodName);
                    if (method != null)
                    {
                        yield return method;
                    }
                }
            }
            private static void Postfix(object __instance) { ClearTagRuntimeText(__instance); }
        }

        // ---- Patient inspection floating tags ----

        [HarmonyPatch]
        private static class HookGetTagsGroup_InspectionTagsControl
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.UI.Inspections.InspectionTagsControl");
                return t == null ? null : AccessTools.PropertyGetter(t, "TagsGroup");
            }
            private static void Postfix(object __instance, object __result)
            {
                ApplyInspectionTagsControl(__instance);
                ApplyUITagsGroup(__result);
            }
        }

        [HarmonyPatch]
        private static class HookAddText_UITagsGroup
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.UI.Tags.UITagsGroup");
                return t == null ? null : AccessTools.Method(t, "AddText", new[] { typeof(string) });
            }
            private static void Prefix(object __instance) { ApplyUITagsGroup(__instance); }
            private static void Postfix(object __instance) { ApplyUITagsGroup(__instance); }
        }

        // ---- Prototype instrument remaining-use notification ----

        [HarmonyPatch]
        private static class HookSubmitText_BubyldaAmmoNotificationController
        {
            private static MethodBase TargetMethod()
            {
                return FindDeclaredMethod(
                    "Assets.Scripts.UI.Controls.BubyldaAmmoNotificationController",
                    "SubmitText",
                    new[] { typeof(string) });
            }
            private static void Postfix(object __instance) { ApplyBubyldaAmmoNotificationController(__instance); }
        }

        // ---- Full-screen Mind Palace thoughts UI ----

        [HarmonyPatch]
        private static class HookInitialize_ThoughtController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.UI.Dialogs.ThoughtController");
                return t == null ? null : AccessTools.Method(t, "Initialize");
            }
            private static void Postfix(object __instance) { ApplyThoughtController(__instance); }
        }

        [HarmonyPatch]
        private static class HookSetText_ThoughtController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.UI.Dialogs.ThoughtController");
                return t == null ? null : AccessTools.Method(t, "SetText", new[] { typeof(string) });
            }
            private static void Prefix(object __instance, string text)
            {
                ApplyThoughtController(__instance);
                LogThoughtText(text);
            }
            private static void Postfix(object __instance) { ApplyThoughtController(__instance); }
        }

        [HarmonyPatch]
        private static class HookUpdateText_ThoughtController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.UI.Dialogs.ThoughtController");
                return t == null ? null : AccessTools.Method(t, "UpdateText");
            }
            private static void Postfix(object __instance) { ApplyThoughtController(__instance); }
        }

        // ---- Mind palace 3D entity controllers ----

        [HarmonyPatch]
        private static class HookActivate_MindMap3dEntityController
        {
            private static MethodBase TargetMethod()
            {
                return FindMethodByName(
                    "Assets.Scripts.Game.Tags.Controllers.MindMap3dEntityController",
                    TagsActivateMethodName);
            }
            private static void Postfix(object __instance) { Apply(__instance); }
        }

        [HarmonyPatch]
        private static class HookInit_MindMap3dEntityController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.MindMap3dEntityController");
                return t == null ? null : AccessTools.Method(t, "InitializeMindMap3d");
            }
            private static void Postfix(object __instance) { Apply(__instance); }
        }

        [HarmonyPatch]
        private static class HookSetScreenText_MindMap3dEntityController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.MindMap3dEntityController");
                return t == null ? null : AccessTools.Method(t, "SetScreenText", new[] { typeof(int), typeof(string) });
            }
            private static void Postfix(object __instance) { Apply(__instance); }
        }

        [HarmonyPatch]
        private static class HookActivate_WallMindMap3dEntityControllerBase
        {
            private static MethodBase TargetMethod()
            {
                return FindMethodByName(
                    "Assets.Scripts.Game.Tags.Controllers.WallMindMap3dEntityControllerBase",
                    TagsActivateMethodName);
            }
            private static void Postfix(object __instance) { Apply(__instance); }
        }

        [HarmonyPatch]
        private static class HookInit_WallMindMap3dEntityControllerBase
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.WallMindMap3dEntityControllerBase");
                return t == null ? null : AccessTools.Method(t, "InitializeMindMap3d");
            }
            private static void Postfix(object __instance) { Apply(__instance); }
        }

        [HarmonyPatch]
        private static class HookRepositionMinds_WallMindMap3dEntityControllerBase
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.WallMindMap3dEntityControllerBase");
                return t == null ? null : AccessTools.Method(t, "RepositionMinds");
            }
            private static bool Prefix(object __instance)
            {
                if (TryPopulateWallMindFallback(__instance))
                {
                    return false;
                }
                return true;
            }
        }

        [HarmonyPatch]
        private static class HookSetScreenText_WallMindMap3dEntityControllerBase
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.WallMindMap3dEntityControllerBase");
                return t == null ? null : AccessTools.Method(t, "SetScreenText", new[] { typeof(int), typeof(string) });
            }
            private static bool Prefix(object __instance, int index, string text)
            {
                // WallMindMap3dEntityControllerBase.RepositionMinds already localized the tag
                // before calling SetScreenText. The original SetScreenText localizes the text
                // again, which can turn Simplified Chinese strings into an empty miss.
                return SetListTextDirect(__instance, "textMeshPros", index, text, true);
            }
            private static void Postfix(object __instance) { Apply(__instance); }
        }

        [HarmonyPatch]
        private static class HookActivate_WallMindMap3dHintsController
        {
            private static MethodBase TargetMethod()
            {
                return FindMethodByName(
                    "Assets.Scripts.Game.Tags.Controllers.WallMindMap3dHintsController",
                    TagsActivateMethodName);
            }
            private static void Postfix(object __instance) { Apply(__instance); }
        }

        [HarmonyPatch]
        private static class HookInit_WallMindMap3dHintsController
        {
            private static MethodBase TargetMethod()
            {
                var t = AccessTools.TypeByName("Assets.Scripts.Game.Tags.Controllers.WallMindMap3dHintsController");
                return t == null ? null : AccessTools.Method(t, "InitializeMindMap3d");
            }
            private static void Postfix(object __instance) { Apply(__instance); }
        }
    }
}
