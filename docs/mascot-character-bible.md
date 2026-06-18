# ShoutOut Mascot Character Bible

Use this as the stable visual spec for generated mascot art.

## Core Character

ShoutOut's mascot is a small, round, friendly navy-blue crab wearing headphones and carrying a boom microphone. The current best source of truth is the blue app-icon crab: round face/shell, oversized chunky claws, simple happy face, and soft ice-blue app-icon energy. The mascot should be cute first and anatomically simplified second. Do not make it more realistic if that makes it less cute.

## Silhouette

- Body: squat round shell, close to a circle or soft rounded oval, like the current blue app-icon crab.
- Proportions: big head/body, oversized claws, tiny or mostly hidden legs.
- Pose: front-facing or slight 3/4 mascot pose like the icon. A subtle side-scuttle is okay only if it preserves the same cute round icon proportions.
- Outline: chunky dark navy pixel outline.
- Avoid: teardrop body, pear body, tall body, long neck, human torso, human legs, feet, shoes, knees, biped stance.

## Anatomy

- Claws: exactly two visible oversized chunky claws.
- Main claw: one claw can hold the boom microphone.
- Second claw: visible and cute, either waving, resting, or balancing the pose.
- Legs: zero to four short visible crab legs total. It is okay for legs to be mostly hidden by the big shell and claws.
- Leg detail: legs should read as tiny cute crab points, not many spider legs.
- Color: legs should stay navy/blue with subtle lighter blue highlights, not orange.
- Avoid: missing claw, more than four visible legs, realistic leg rows, long insect legs, human feet, orange legs.

## Face

- Expression: simple, happy, calm.
- Eyes: two dark navy eyes with small white pixel highlights.
- Mouth: tiny smile, no teeth.
- Avoid: aggressive expression, realistic crab face, fangs, eyebrows.

## Gear

- Headphones: dark teal headphones with rounded ear cups and a simple headband. They should be teal/navy balanced, not bright electric blue.
- Boom microphone: dark handle with gray foam windscreen, clearly readable but not oversized.
- The mic should sit near one claw or across the front of the body.

## Color Palette

- Shell: deep sea-blue, navy, or indigo.
- Headphones: dark teal, muted aqua, and navy.
- Claws and leg tips: navy/blue, with tiny coral accents allowed only as cheeks or small shell highlights.
- Highlights: light cyan and off-white.
- Outline: dark navy, not pure black.
- Avoid: black crab body, yellow background, muddy brown, dominant beige, orange legs, orange claws.

## Pixel-Art Rules

- High-resolution pixel art with crisp, chunky shapes.
- Clean readable silhouette at small sizes.
- No text, no watermark, no photorealism.
- For web cutouts, generate on a flat #ff00ff chroma-key background and remove it locally.

## Animation Sets

- `idle-walk`: no boom microphone. Use for normal idle movement, walking, and wall traversal.
- `recording-boom`: boom microphone visible. Use only when recording/listening. Prefer a still pose in UI; recording should feel calm and steady.
- Keep both sets visually identical except for the boom microphone and subtle pose changes.
- The website and macOS app should share the same canonical frames where possible.

## Reusable Generation Prompt

Create a high-resolution pixel-art sticker cutout of the ShoutOut mascot based on the current blue app-icon crab: a small, round, friendly navy-blue crab wearing dark teal headphones and holding a boom microphone. Preserve the app-icon character's cute proportions: big squat circular shell, oversized chunky navy-blue claws, tiny or mostly hidden navy-blue legs, dark navy pixel outlines, simple happy eyes with white highlights, and a tiny smile. One claw holds the boom microphone and the other claw remains clearly visible. The pose should feel like the icon crab stepped out of the tile, not like a realistic crab walking.

Use a flat solid #ff00ff chroma-key background for removal. No shadows, no texture, no gradients, no floor plane. Do not use #ff00ff in the subject.

Avoid teardrop body, pear body, black crab body, yellow background, missing claw, orange legs, orange claws, bright blue headphones, more than four visible legs, realistic leg rows, spider legs, insect legs, human legs, feet, shoes, knees, biped stance, upright walking pose, scary expression, text, watermark, photorealism.
