# feedback/3 文本修改对比（按用户汇总修正）

生成时间：2026-06-11  
修改范围：`09_patch_work/overlay_cn_textassets_20260422`  
处理原则：保留草原语、拉丁语、希腊语原文，只补中文括注；明显格式错误和术语不统一直接修；姓名、病历、原文需查证项不硬改。

## 已写入的修改

| 编号 | 类型 | 位置 | 修改前问题 | 修改后 |
|---|---|---|---|---|
| A2 | 草原语少翻译 | `Day8_Q5_SteppeCitizen_What` | `üshöö üghi`、`Oyohon` 裸露 | 补为 `üshöö üghi（不见了）`、`Oyohon（缝出来）` |
| A3 | 拉丁语少翻译 | `Day2_Q11_Khan_SaveTheKid.2740` | `discimus` 未译 | `discimus（我们学习）` |
| A4-A6 | 草原语少翻译 | `Day3_Q10_Herdsman_BuyMyBull` | `tagnuul`、`gartsiin talbay`、`avga akh`、`örsöldögch` 裸露 | 分别补为 `探子`、`集市广场`、`叔伯`、`对手` |
| A8 | 草原语少翻译 | `Day11_Q10_Courier_Haruspex.45308` / `Day4_Q6_Haruspex_SpecialPatient.15002` | `门德` 看似人名 | 改为 `Mendē（你好）` / `Mendee（你好）` |
| A10 | 术语不统一 | 多处 `Day4_Q6`、`Day5_Q7`、`Day6_Q1` | `坎朱尔` 与角色名 `甘珠尔` 不一致 | 全部统一为 `甘珠尔` |
| A11 / C1 | 注释重复 | `Hospital_Vasiliy_Boy.7946` | 整句草原语和中文释义重复堆叠 | 保留 `Sayn bayna, erdem.（你好，学者。）`，后半句另译 |
| A12-A13 | 草原语少翻译 | `Hospital_Vasiliy_Boy.12836/.22877` | `Aydahamni hürene`、`büü alysh`、`Tere namaye abarba` 裸露 | 补为 `你闻起来像危险`、`别靠近`、`他救了我` |
| A14-A19 | 草原语少翻译 | `Hospital_Oktay_Brides` | `Ende yamar zhehteib`、`Zhegtei`、`khyn`、`Eryuu khyn`、`Ekhe sula` 裸露 | 分别补为 `这里多奇怪`、`奇怪`、`人`、`坏人`、`根基薄弱` |
| A22-A24 | 草原语少翻译 | `Day6_Q11_InfectingTheBull` | `khamgaalna`、`aladag`、`Bukhanuud ubdedeggui`、`kheregghyy` 裸露 | 分别补为 `保护`、`拖下去`、`公牛不会生病`、`没用` |
| A25-A27 | 拉丁语少翻译 | `Day0_Q8_Prokop_FateIsSealed` | 拉丁短句未译 | 补 `学院厌恶真空`、`谁也不能冒犯我而不受惩罚`、`作为报酬的一部分` |
| A28-A31 | 草原语少翻译 | `Hospital_Tuutey_Interview` | `ukhedel`、`urmaan`、`bos`、`aman`、`Kheterme ekheer bü uu` 裸露 | 补 `生命`、`元气`、`公牛`、`口`、`不能喝太多` |
| A32-A35 | 草原语少翻译 | `Day8_Q5_SteppePeople_Murderers` / `Day9_Q16_BullEaters_EatingBull` | 草原语句未译 | 补 `愿他的血温热大地`、`把自己托付给我们`、`我真不敢相信`、`我们吃了公牛`、`它救了我们` |
| A36-A38 | 草原语少翻译 | `Day8_Q9_Diseased_Delirium` / `AskAndAnswers` | `Khara'al idsen bayshin`、`Busad khümü'üs övdöj ühsen`、`sa'ad bolno`、`namaiye sülööl` 裸露 | 补 `被诅咒吞噬的屋子`、`其他人都病死了`、`妨碍她`、`放我走` |
| A39 | 草原语少翻译 | `Day8_Q12_Boulder_Deal.16387` | `Be tereniiye shangha ba ukhaathai ghezhe hanadagh bayghaab` 裸露 | 补 `我原以为他强健而明智` |
| A40 / A42 | 希腊语少翻译 | `Day8_Q6_Crowd_Radio` | 选项中希腊语未译 | 补 `孩子们会没事的，别担心。`、`人应当能够把作者和作品分开。` |
| A43-A45 | 草原语少翻译 | `Day8_Q5_VillageBride_Herbs` | `buyantay`、`khariulakh`、`gürwhal`、`aluurshan`、`khoto zon` 裸露 | 补 `有福之人`、`回答`、`蜥蜴`、`杀人者`、`城里人` |
| A46-A48 | 草原语少翻译 | `Day8_Q5_SteppePeople_Festival` | `tenegh`、`Nanghin shuhan`、`hayn`、`hayn halkhinai temdegh` 裸露 | 补 `傻瓜`、`纯净的血`、`仁慈`、`好兆头` |
| C2-C6 | 草原语少翻译 | `Hospital_Oktay_Interview` / `NewQuestions` | `teneghyyd`、`untarna`、`ekhe kholo`、`ulaan`、`Bee khelekhe, shee bu shaghna` 等裸露 | 补 `傻瓜们`、`熄灭`、`离母亲很远`、`红色`、`我说了，你却不听` |
| C8-C11 | 草原语少翻译 | `Day6_Q11_InfectingTheBull` / `Day7_Q9_Odongh2_Boulder` | `bid end irekh yosgui baisan`、`muukhai unertei`、`Ene ynain`、`Muu ynair` 裸露 | 补 `我们本不该来这里`、`难闻`、`住这儿`、`酸味` |
| D13 | 术语不统一 | `Day4_Q6`、`Day5_Q7`、`Day6_Q1` 等 | `噗粉` 与 Shmowder 术语不统一 | 全部改为 `什莫粉` |
| D16 | 拉丁文缺原文 | `Protocol_TiredParamedic.45511` | 只有中文 `先到者取走猎物。` | 改为 `Abducet praedam, cui occurit prior.（先来的人，带走猎物。）` |
| D25 | 标签错误 | `Day9_Q17.1_Inquisitor_Eeeexperiments.27990` | 出现 `<i/>` | 改为 `</i>` |

## 需要复核的上下文译注

这些已经补入文本，但属于“英文原文也没有给直译，只能按上下文判断”的项目，建议你复看一眼：

| 编号 | 文本 | 当前括注 |
|---|---|---|
| A28-A31 | `ukhedel` / `urmaan` | `生命` / `元气` |
| A32-A35 | `bidenkhee khülisael ghuiba` / `bukha edibebdi` | `把自己托付给我们` / `我们吃了公牛` |
| A36-A38 | `Khara'al idsen bayshin` / `sa'ad bolno` | `被诅咒吞噬的屋子` / `妨碍她` |
| A43-A48 | `Gansal shuhan muue usadhadag` | `愿正义之血洗去恶水` |
| C2-C6 | `udhar` / `mete` | `恩赐` / `外壳` |

## 未直接修改的项目

这些不是简单“补括注”问题，当前没有硬改：

| 编号 | 原因 |
|---|---|
| A7、A16、A20、A41、F1-F4 | 用户汇总为“没问题” |
| A21、B1、C7、D1、D7、D8 | 用户汇总为“已更正” |
| C12、C13 | 需要继续查原文语境，不适合只凭截图改 |
| D2-D6、D9-D12、D14-D24、D26-D28、E1-E2 | 涉及姓名、病历、人物称呼或世界观术语统一，需要按原文、病历、全局术语表排查后再改 |

## 扫描校验

已扫描 `overlay_cn_textassets_20260422`：

- `坎朱尔`：无残留
- `噗粉`：无残留
- `<i/>`：无残留
- `discimus。`：无残留
- `先到者取走猎物。`：无残留
- `???`：无残留
- `？？？`：仅剩两个默认占位名：`Npcs.PlagueBachelor.Name`、`UI.CharacterWindow.Default.DefaultName`

本轮没有执行打包，也没有写入游戏安装目录。
