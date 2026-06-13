using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using BepInEx;
using BepInEx.Logging;
using HarmonyLib;
using UnityEngine;

namespace Pathologic3CnRuntimeOverride
{
    [BepInPlugin(PluginGuid, PluginName, PluginVersion)]
    public sealed class Plugin : BaseUnityPlugin
    {
        public const string PluginGuid = "com.pathologic3.cn.runtimeoverride";
        public const string PluginName = "Pathologic3 CN Runtime Override";
        public const string PluginVersion = "0.1.0";

        private static readonly Dictionary<string, string> Overrides = new Dictionary<string, string>(StringComparer.Ordinal);
        private static readonly List<string> LoadedSources = new List<string>();
        private static readonly HashSet<string> SeenHits = new HashSet<string>(StringComparer.Ordinal);
        private static readonly HashSet<string> SeenMissingLiteralKeys = new HashSet<string>(StringComparer.Ordinal);
        private static readonly HashSet<string> SeenProjectedTextAdjustments = new HashSet<string>(StringComparer.Ordinal);
        private static bool DictionaryInjectionLogged;

        internal static ManualLogSource Log;

        private void Awake()
        {
            Log = Logger;
            ReloadOverrides();

            var harmony = new Harmony(PluginGuid);
            harmony.PatchAll(typeof(Plugin).Assembly);

            Logger.LogInfo(string.Format("Runtime override initialized. Loaded {0} translated keys from {1} file(s).", Overrides.Count, LoadedSources.Count));
            foreach (var source in LoadedSources)
            {
                Logger.LogInfo(string.Format("Translation source: {0}", source));
            }
        }

        internal static bool TryGetOverride(string key, out string value)
        {
            return Overrides.TryGetValue(key, out value);
        }

        private static string ExpandVisibleText(string text)
        {
            if (string.IsNullOrEmpty(text) || text.IndexOf('{') < 0)
            {
                return text;
            }

            var normalized = text.Replace("\r\n", "\n").Replace("\r", "\n");
            var lines = normalized.Split('\n');
            var changed = false;

            for (var i = 0; i < lines.Length; i++)
            {
                lines[i] = ExpandVisibleLine(lines[i], ref changed);
            }

            if (!changed)
            {
                return text;
            }

            return string.Join("\n", lines);
        }

        private static string ExpandVisibleLine(string line, ref bool changed)
        {
            if (string.IsNullOrEmpty(line))
            {
                return line;
            }

            var fullLineMatch = Regex.Match(line, "^\\{([^{}]+)\\}\\s*(.*)$");
            if (fullLineMatch.Success)
            {
                var key = fullLineMatch.Groups[1].Value.Trim();

                string translated;
                if (TryGetOverride(key, out translated))
                {
                    changed = true;
                    return translated;
                }

                if (Log != null
                    && key.StartsWith("UI.", StringComparison.Ordinal)
                    && SeenMissingLiteralKeys.Add(key))
                {
                    Log.LogWarning(string.Format("Literal UI key was assigned to a text component but no runtime override entry was found: {0}", key));
                }

                return line;
            }

            var inlineMatches = Regex.Matches(line, "\\{([^{}]+)\\}");
            if (inlineMatches.Count == 0)
            {
                return line;
            }

            var rebuilt = line;
            for (var i = inlineMatches.Count - 1; i >= 0; i--)
            {
                var match = inlineMatches[i];
                string translated;
                if (!TryGetOverride(match.Groups[1].Value.Trim(), out translated))
                {
                    continue;
                }

                rebuilt = rebuilt.Substring(0, match.Index) + translated + rebuilt.Substring(match.Index + match.Length);
                changed = true;
            }

            return rebuilt;
        }

        private static string AdjustProjectedWorldText(object textComponent, string text)
        {
            if (string.IsNullOrEmpty(text))
            {
                return text;
            }

            var component = textComponent as Component;
            if (component == null)
            {
                return text;
            }

            string transformPath;
            if (!ShouldAdjustProjectedWorldText(component, text, out transformPath))
            {
                return text;
            }

            var normalized = text.Replace("\r\n", "\n").Replace("\r", "\n");
            var firstLine = normalized
                .Split('\n')
                .Select(x => x.Trim())
                .FirstOrDefault(x => !string.IsNullOrEmpty(x));

            if (string.IsNullOrEmpty(firstLine))
            {
                return text;
            }

            if (HasCjk(firstLine) && firstLine.Length > 14)
            {
                firstLine = firstLine.Substring(0, 14) + "…";
            }
            else if (firstLine.Length > 24)
            {
                firstLine = firstLine.Substring(0, 24) + "…";
            }

            ApplyProjectedTextStyle(textComponent);

            if (SeenProjectedTextAdjustments.Add(transformPath) && Log != null)
            {
                Log.LogInfo(string.Format("Adjusted projected world text at {0}: {1}", transformPath, firstLine));
            }

            return firstLine;
        }

        private static bool ShouldAdjustProjectedWorldText(Component component, string text, out string transformPath)
        {
            transformPath = BuildTransformPath(component.transform);

            if (component.GetComponentInParent(typeof(Canvas)) != null)
            {
                return false;
            }

            var typeName = component.GetType().FullName ?? component.GetType().Name;
            if (typeName.IndexOf("UGUI", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return false;
            }

            var pathLower = transformPath.ToLowerInvariant();
            var suspiciousPath =
                pathLower.Contains("cloud") ||
                pathLower.Contains("project") ||
                pathLower.Contains("notebook") ||
                pathLower.Contains("mind") ||
                pathLower.Contains("thought");

            var normalized = text.Replace("\r\n", "\n").Replace("\r", "\n");
            var hasMultipleLines = normalized.IndexOf('\n') >= 0;
            var isLongCjkText = HasCjk(normalized) && normalized.Length > 20;
            var isLongAsciiText = normalized.Length > 32;

            return suspiciousPath || hasMultipleLines || isLongCjkText || isLongAsciiText;
        }

        private static bool HasCjk(string text)
        {
            if (string.IsNullOrEmpty(text))
            {
                return false;
            }

            foreach (var ch in text)
            {
                if (ch >= 0x4E00 && ch <= 0x9FFF)
                {
                    return true;
                }
            }

            return false;
        }

        private static string BuildTransformPath(Transform transform)
        {
            if (transform == null)
            {
                return "<null>";
            }

            var names = new List<string>();
            while (transform != null)
            {
                names.Add(transform.name);
                transform = transform.parent;
            }

            names.Reverse();
            return string.Join("/", names.ToArray());
        }

        private static void ApplyProjectedTextStyle(object textComponent)
        {
            var type = textComponent.GetType();
            var fontSize = GetFloatMember(textComponent, type, "fontSize");

            SetMember(type, textComponent, "enableAutoSizing", true);
            SetMember(type, textComponent, "enableWordWrapping", false);
            SetMember(type, textComponent, "maxVisibleLines", 1);

            if (fontSize > 0f)
            {
                SetMember(type, textComponent, "fontSizeMax", fontSize);
                SetMember(type, textComponent, "fontSizeMin", Mathf.Max(1f, fontSize * 0.45f));
            }

            var overflowModeType = AccessTools.TypeByName("TMPro.TextOverflowModes");
            if (overflowModeType != null)
            {
                try
                {
                    var truncateValue = Enum.Parse(overflowModeType, "Truncate");
                    SetMember(type, textComponent, "overflowMode", truncateValue);
                }
                catch
                {
                }
            }
        }

        private static float GetFloatMember(object instance, Type type, string name)
        {
            var property = AccessTools.Property(type, name);
            if (property != null && property.CanRead)
            {
                var value = property.GetValue(instance, null);
                if (value is float)
                {
                    return (float)value;
                }
            }

            var field = AccessTools.Field(type, name);
            if (field != null)
            {
                var value = field.GetValue(instance);
                if (value is float)
                {
                    return (float)value;
                }
            }

            return 0f;
        }

        private static void SetMember(Type type, object instance, string name, object value)
        {
            var property = AccessTools.Property(type, name);
            if (property != null && property.CanWrite)
            {
                try
                {
                    property.SetValue(instance, value, null);
                }
                catch
                {
                }

                return;
            }

            var field = AccessTools.Field(type, name);
            if (field != null)
            {
                try
                {
                    field.SetValue(instance, value);
                }
                catch
                {
                }
            }
        }

        private static void ReloadOverrides()
        {
            Overrides.Clear();
            LoadedSources.Clear();
            DictionaryInjectionLogged = false;

            foreach (var candidate in GetCandidatePaths())
            {
                if (!File.Exists(candidate))
                {
                    continue;
                }

                var countBefore = Overrides.Count;
                LoadTsv(candidate);
                var added = Overrides.Count - countBefore;
                LoadedSources.Add(candidate);
                if (Log != null)
                {
                    Log.LogInfo(string.Format("Loaded {0} entries from {1}", added, candidate));
                }
            }

            if (LoadedSources.Count == 0)
            {
                if (Log != null)
                {
                    Log.LogWarning("No translation TSV found. Plugin is active, but nothing will be overridden.");
                }
                foreach (var candidate in GetCandidatePaths())
                {
                    if (Log != null)
                    {
                        Log.LogWarning(string.Format("Missing translation TSV candidate: {0}", candidate));
                    }
                }
            }
        }

        private static IEnumerable<string> GetCandidatePaths()
        {
            yield return Path.Combine(Paths.GameRootPath, "BepInEx", "plugins", "Pathologic3CnRuntimeOverride", "overrides.tsv");
            yield return Path.GetFullPath(Path.Combine(Paths.GameRootPath, "..", "05_day1_text", "17_batch1_opening_translation_draft.tsv"));
        }

        private static void LoadTsv(string path)
        {
            foreach (var rawLine in File.ReadLines(path, Encoding.UTF8))
            {
                var line = rawLine.TrimEnd('\r', '\n');
                if (string.IsNullOrWhiteSpace(line))
                {
                    continue;
                }

                if (line.StartsWith("asset_base\tkey\tzh_draft", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var firstTab = line.IndexOf('\t');
                if (firstTab < 0)
                {
                    continue;
                }

                var secondTab = line.IndexOf('\t', firstTab + 1);
                if (secondTab < 0)
                {
                    continue;
                }

                var key = line.Substring(firstTab + 1, secondTab - firstTab - 1).Trim();
                var text = line.Substring(secondTab + 1);

                if (string.IsNullOrWhiteSpace(key) || string.IsNullOrWhiteSpace(text))
                {
                    continue;
                }

                Overrides[key] = DecodeEscapes(text);
            }
        }

        private static string DecodeEscapes(string text)
        {
            return text
                .Replace("\\n", "\n")
                .Replace("\\t", "\t");
        }

        [HarmonyPatch]
        private static class LocalizationServiceGetTextPatch
        {
            private static MethodBase TargetMethod()
            {
                var localizationType = AccessTools.TypeByName("Localizations.LocalizationService");
                return AccessTools.Method(localizationType, "GetText", new[] { typeof(string) });
            }

            private static void Postfix(string tag, ref string __result)
            {
                if (string.IsNullOrEmpty(tag))
                {
                    return;
                }

                string translated;
                if (!TryGetOverride(tag, out translated))
                {
                    return;
                }

                __result = translated;

                if (SeenHits.Add(tag))
                {
                    if (Log != null)
                    {
                        Log.LogInfo(string.Format("Applied runtime override: {0}", tag));
                    }
                }
            }
        }

        [HarmonyPatch]
        private static class LocalizationServiceLoadTextPatch
        {
            private static MethodBase TargetMethod()
            {
                var localizationType = AccessTools.TypeByName("Localizations.LocalizationService");
                var dictionaryType = typeof(Dictionary<string, string>);
                return AccessTools.Method(localizationType, "LoadText", new[] { typeof(string), dictionaryType });
            }

            private static void Postfix(string data, Dictionary<string, string> languages)
            {
                if (languages == null || Overrides.Count == 0)
                {
                    return;
                }

                var injected = 0;
                foreach (var pair in Overrides)
                {
                    if (!languages.ContainsKey(pair.Key) || !string.Equals(languages[pair.Key], pair.Value, StringComparison.Ordinal))
                    {
                        languages[pair.Key] = pair.Value;
                        injected++;
                    }
                }

                if (injected > 0 && Log != null && !DictionaryInjectionLogged)
                {
                    DictionaryInjectionLogged = true;
                    Log.LogInfo(string.Format("Injected {0} runtime override entries into localization dictionary.", injected));
                }
            }
        }

        [HarmonyPatch]
        private static class TmpTextSetterPatch
        {
            private static MethodBase TargetMethod()
            {
                var tmpTextType = AccessTools.TypeByName("TMPro.TMP_Text");
                return AccessTools.PropertySetter(tmpTextType, "text");
            }

            private static void Prefix(object __instance, ref string value)
            {
                value = ExpandVisibleText(value);
                value = AdjustProjectedWorldText(__instance, value);
            }
        }

        [HarmonyPatch]
        private static class UnityTextSetterPatch
        {
            private static MethodBase TargetMethod()
            {
                var uiTextType = AccessTools.TypeByName("UnityEngine.UI.Text");
                return AccessTools.PropertySetter(uiTextType, "text");
            }

            private static void Prefix(ref string value)
            {
                value = ExpandVisibleText(value);
            }
        }
    }
}
