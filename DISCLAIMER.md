# 免责声明 · Disclaimer

> 最后更新：2026 年 10 月 29 日
> 适用范围：本仓库（源代码、构建脚本、文档、示例）以及由本仓库构建出的可执行程序 `BreezeTTS Lite.app`。

**在下载、安装、复制、编译或使用本项目之前，请完整阅读本声明。你一旦开始使用，即视为已阅读、理解并同意本声明的全部内容。如果你不同意，请立即停止使用并删除本项目及其全部副本。**

---

## 一、项目性质

1. 本项目是一个**个人独立开发的开源实验性项目**，用于学习与研究 macOS 原生界面（SwiftUI）与本地语音合成推理（Breeze-TTS-2.cpp / ggml）的工程实现。
2. 本项目**不是商业产品**，不提供任何形式的商业服务、订阅、售后支持或服务等级承诺。
3. 本项目**完全在本地运行**：不设服务器、不上传你的文本、音频、音色数据或使用记录，也不收集任何遥测数据。模型文件由你自行从第三方地址下载。
4. 本项目与 Breeze-TTS-2.cpp、llama.cpp 等上游项目的作者**没有隶属、合作或背书关系**。

## 二、使用限制

本项目以开源许可证（Apache License 2.0，见 `LICENSE`）授权你使用，但**在以下场景中，作者明确不支持、不认可，并不承担任何责任**：

1. **仅供个人学习、研究与自用。** 请勿将其作为对外提供的在线服务、付费产品、SaaS 平台或硬件预装软件的组成部分。
2. **禁止任何违法用途。** 包括但不限于：制作、复制、传播违法违规信息；冒充他人身份；实施诈骗、敲诈、骚扰、诽谤；伪造证据、伪造录音；规避平台审核；以及其他违反中华人民共和国法律法规或你所在司法辖区法律的行为。
3. **禁止侵害他人合法权益。** 包括但不限于：未经许可克隆、模仿他人声音；未经许可使用他人姓名、肖像、商标、作品；侵犯著作权、商标权、人格权、名誉权、隐私权与个人信息权益。
4. **禁止用于可能造成人身或财产损害的场景。** 例如医疗诊断与治疗建议、法律意见、金融投资决策、紧急救援、安防与身份核验、司法取证等；本项目的输出**不具备任何专业效力，也不可作为事实依据**。
5. **禁止规避、删除或篡改**本项目输出内容中的 AI 生成标识、水印或元数据。

如果你希望将本项目用于商业用途或对外提供服务，**请自行完成全部合规评估与资质要求**（见第四节），并自行承担相应责任；作者不提供任何合规承诺或法律意见。

## 三、声音克隆的特别提示（重要）

本项目支持"上传参考音频 → 克隆音色"的功能。声音属于**受法律保护的人格权益**，请务必注意：

1. 你**只能克隆自己的声音**，或已取得声音权利人**明确、可举证、范围清晰的书面授权**的声音。
2. 即使取得授权，也**不得**生成让听众误以为是该权利人真实说法的内容（包括但不限于"代言""表态""承诺""证词"等）。
3. 你**不得**将克隆出的音色用于冒充他人、伪造通话录音、制造虚假新闻、实施电信网络诈骗等行为。此类行为在中国大陆可能构成《刑法》规定的诈骗罪、招摇撞骗罪，或违反《民法典》关于声音权益参照肖像权保护的规定（第一千零二十三条），以及《个人信息保护法》关于敏感个人信息处理的规定。
4. 你应**妥善保管**自己保存的音色文件与参考音频。本项目将数据存放在本机 `~/Library/Application Support/BreezeTTS Lite/`，**未做任何加密**；任何能访问该目录的人或程序都可以读取。因本机失窃、恶意软件、共享电脑等原因造成的数据泄露，由你自行承担。
5. 作者**不会**、也**无法**审查你生成的任何内容，**不对**你使用克隆音色产生的任何后果负责。

## 四、AI 生成内容的标识与合规义务（中国大陆用户）

依据《中华人民共和国网络安全法》《数据安全法》《个人信息保护法》《生成式人工智能服务管理暂行办法》《互联网信息服务深度合成管理规定》《人工智能生成合成内容标识办法》等规定：

1. 你利用本项目生成的内容属于**深度合成 / AI 生成合成内容**，在公开发布、传播时**应当依法进行显著标识**，不得删除、篡改、伪造标识。
2. 你**不得**利用本项目生成并传播虚假信息，不得生成侵害他人权益、危害国家安全与公共利益的内容。
3. 若你将本项目用于向**境内公众提供生成式人工智能服务**，你将成为该服务的"服务提供者"，需自行履行备案/安全评估、内容审核、用户实名、投诉处理、数据安全等全部法定义务。**本项目作者不是该服务的提供者，不承担上述义务与责任。**
4. 其他国家和地区用户，请自行遵守当地关于 AI 生成内容、声音权益、个人信息保护的强制性规定。

## 五、内容与输出责任

1. 本项目仅为**工具**。你输入的文字、上传的音频、选择的音色，以及由此生成的音频内容，其**合法性、准确性、正当性完全由你负责**。
2. 语音合成结果可能存在**错误、失真、漏读、语气偏差、发音不准**等情况，**不得**作为事实陈述、法律证据或对外承诺使用。
3. 因模型权重、第三方依赖、操作系统更新、硬件差异等导致的输出异常或不可用，作者不承担责任。

## 六、无担保与责任限制

1. 本项目按**"现状"（AS IS）**提供，**不附带任何明示或默示的担保**，包括但不限于适销性、特定用途适用性、不侵权、无错误、不中断的担保。
2. 在适用法律允许的最大范围内，**作者及贡献者不对任何直接、间接、偶然、特殊、惩罚性或后果性损害承担责任**，包括但不限于利润损失、数据丢失、业务中断、名誉损害、第三方索赔，无论其基于合同、侵权或其他法律理论，也无论作者是否已被告知该等损害的可能性。
3. 你使用本项目即表示**自愿承担全部风险**。若你所在司法辖区不允许排除默示担保或限制责任，则上述限制在该辖区法律允许的最小范围内适用。

## 七、知识产权与"侵权告知—及时下架"

1. 本项目**源代码**依 Apache License 2.0 开源（见 `LICENSE`），你可在许可证条款下自由使用、修改、分发。
2. 本项目**不包含、不分发任何模型权重文件**。模型由你在运行时从第三方地址下载，其著作权与使用条款归模型权利人所有；下载与使用模型产生的合规问题由你自行判断与承担。
3. 本项目引用的第三方组件（Breeze-TTS-2.cpp、llama.cpp 等）版权归各自作者所有，详见 `NOTICE` 与各子目录中的许可证文件。
4. 本项目使用的名称、图标、界面设计如无意侵犯了任何第三方的商标权、著作权或其他权利，**纯属非故意**。
5. **侵权告知与下架承诺：**
   - 若你认为本项目（含源代码、文档、图标、名称或打包产物）侵犯了你的合法权益，请通过本仓库的 **Issues** 提交告知，或在仓库主页找到维护者联系方式后直接联系。
   - 告知时请尽量提供：**权利证明**（权属文件、登记证书、原始发布链接等）、**涉嫌侵权内容的具体位置**（文件路径、截图、链接）、**你的联系方式**，以及一份**善意声明**（声明所述内容真实、你系权利人或有资格代为主张）。
   - 维护者收到**有效告知**后，将及时核实，并在**确认后 72 小时内**删除、替换或下架相关内容；对明显违法或明显侵权的情形，将在 **24 小时内**先行下架再核实。
   - 若你对下架有异议，可提交反通知与相应证明材料，维护者将依同样流程复核。
   - 对于**恶意投诉、虚假投诉**，维护者保留追究相应责任的权利。

## 八、第三方链接与下载源

本项目运行时会访问第三方模型托管地址（如 `hf-mirror.com`、`huggingface.co`）下载模型。这些站点**不受本项目控制**，其可用性、内容安全性与隐私政策由该站点自行负责。作者不对第三方站点的内容、可用性及由此产生的任何损害承担责任。

## 九、适用法律与争议解决

本声明适用**中华人民共和国大陆地区法律**（不含冲突法规则）。因本项目产生的争议，双方应友好协商解决；协商不成的，提交维护者所在地有管辖权的人民法院处理。若你所在地区的强制性法律赋予你不可放弃的权利，则该等权利不受本声明影响。

## 十、声明的变更

维护者有权随时更新本声明，更新后的版本将在本仓库发布并注明日期。你继续使用本项目即视为接受更新后的声明。

---

## English Summary (non-binding)

BreezeTTS Lite is a **personal, non-commercial, experimental open-source project** provided **"AS IS", without warranty of any kind**. It runs **entirely on your machine** and collects no data. You are **solely responsible** for everything you generate with it.

You must **not** use it to: violate any law; impersonate any person; clone a voice without the speaker's explicit, verifiable consent; create or spread disinformation, fraud, harassment, or defamatory material; misrepresent synthetic audio as genuine recordings; or remove AI-generated content labels.

Voice is protected by personality rights. **Only clone your own voice, or a voice you are legally authorized to use.** Publishing AI-generated audio may require clear labeling under applicable law (e.g. China's deep-synthesis and AIGC-labeling rules).

The authors and contributors accept **no liability** for any direct, indirect, incidental, or consequential damages arising from the use of this software.

**Takedown policy:** If you believe any part of this repository infringes your rights, please open an Issue with proof of ownership and the exact location of the allegedly infringing material. Verified requests will be actioned **within 72 hours** (within 24 hours for clearly unlawful or clearly infringing content). Good-faith disputes are welcome.

Third-party components retain their own licenses — see `LICENSE`, `NOTICE`, and `Breeze-TTS-2.Cpp/LICENSE`. Model weights are **not** distributed here and remain subject to their own terms.
