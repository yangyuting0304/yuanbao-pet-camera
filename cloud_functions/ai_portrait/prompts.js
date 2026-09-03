// 风格提示词映射。
// 与 lib/data/ai_portrait_service.dart 的 kPortraitStyles 保持一致。
// 前端只传 styleId，服务端根据 styleId 取对应的提示词。

module.exports = {
  oil:
    "Oil portrait on linen canvas. Thick impasto brushstrokes, visible palette knife texture, Rembrandt-style chiaroscuro lighting from upper left, strong tonal contrast. Warm amber/golden hues with deep burnt umber shadows. Muted dark velvet backdrop with shallow bokeh. Strictly preserve the subject's original facial geometry, exact coat color, and physical posture \u2013 no anthropomorphism. Photorealistic rendering, canvas grain visible.",
  watercolor:
    "Watercolor painting on cold-pressed paper. Visible paper tooth, transparent washes with blooming edges. High-key pastel palette (pale blue, rose, mint), generous white negative space. Loose brushwork, wet-on-wet diffusion. Gentle morning light. The subject's unique facial markings, fur color zones, and original stance must be exactly replicated. Clean white border, minimal background.",
  anime:
    "Japanese anime cel-shaded illustration. Clean ink outlines, large expressive eyes with star-shaped highlights. Slightly chibi proportions, soft cel gradients on shadows. Vibrant pastel colors against a dreamy sky background. Maintain the subject's ear shape, muzzle length, and distinct color patches \u2013 stylize only rendering, never morphology.",
  vintage:
    "1980s analog film photography \u2013 Kodak Portra tone. Warm amber/yellow fade, organic film grain, subtle light leaks in corner, heavy vignette. Soft halation around highlights, low contrast, nostalgic atmosphere. The subject's facial structure, coat texture, and exact positioning must remain photorealistically intact \u2013 no artistic distortion.",
  royal:
    "Traditional Chinese Gongbi fine-brush painting on silk. Iron-wire linework defining contours, natural mineral pigments (cinnabar, malachite). Decorative peony blossoms, Xiangyun clouds, Ming-style seal and calligraphy. Asymmetric balanced composition with negative space. The subject's muzzle proportion, ear set, and distinctive markings must be rendered with accuracy \u2013 only the medium changes.",
  festive:
    "Cozy festive indoor scene with cinematic lighting. Warm Christmas tree fairy lights (bokeh in background), gift boxes in crimson, emerald, gold. Soft falling snowflakes, firelight warmth. Volumetric light rays. The subject's facial features, full coat color, and posture are non-negotiable \u2013 maintain realistic proportions amid the holiday setting.",

  // AI 一键成片「AI 优化」：把用户输入的简短场景描述扩写为详细、连贯、
  // 可直接用于图生视频的完整提示词（万相 wan2.7-i2v）。
  // 调用时把 {{用户输入}} 占位符替换为用户输入，交给文本大模型扩写。
  PROMPT_OPTIMIZER: `你是一位专业的图生视频提示词工程师。你的任务是将用户提供的简短场景描述，转化为一个详细、连贯、可直接用于图生视频（Image-to-Video）的完整提示词。

【输入】用户会给出一个简单的场景，可能包含角色（如"猫"、"狗"等动物）和动作主题（如"做咖啡"、"踢足球"、"西游记名场面"等）。

【输出要求】
1. **物种通用性**：输出中不得指定任何具体动物品种（如橘猫、金毛），一律使用"毛孩子"、"小家伙"、"它"等代称，因为实际视频的主角由用户上传的固定图片决定，不得改变其外形。
2. **完整动作链**：必须设计从开始到结束的完整流程，包含至少3～5个连续动作环节，确保总时长超过10秒。每个环节要有具体的肢体动作描写（如爪子的抓握、嘴的衔取、身体跳跃、转身等），动作之间衔接自然。
3. **环境与氛围**：描述光线、色彩、声音、气味等感官细节，营造沉浸式场景。
4. **镜头语言**：适当加入景别变化（如全景、中景、特写）、机位移动（推、拉、摇、移），增强叙事节奏。
5. **多角色处理**：如果场景涉及多个角色（如孙悟空与白骨精），默认由同一只毛孩子通过道具、服饰切换来分饰多角，输出中应明确分幕，并说明变装/换道具的方式。
6. **结束动作**：每个场景必须以一个明确的"收尾动作"结束，如递出物品、转身离开、定格姿态等，让视频有完整感。
7. **附加通用提示**：在提示词末尾，添加一条稳定画面、避免形变的指导（如"动作全程保持毛孩子原有外形和毛色不变，以自然匀速运动为主，避免扭曲变形"）。

【输出格式】
- 直接输出优化后的完整提示词，无需额外说明。
- 如果需要分幕，用"第一幕/第二幕……"或"场景切换"清晰划分。
- 使用流畅的叙述性语言，每句描述一个动作或氛围，避免列表式语句。

现在，请根据用户输入："{{用户输入}}" 生成优化后的图生视频提示词。`,
};
