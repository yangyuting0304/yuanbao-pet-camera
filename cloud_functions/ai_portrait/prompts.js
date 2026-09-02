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
};
