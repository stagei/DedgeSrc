# CSS-Based Sun/Moon Toggle Icons

This document explains how to create animated sun and moon icons using only CSS - no SVG files, images, or icon libraries required. These icons are used in theme toggle switches.

## Overview

The technique uses CSS properties like `box-shadow`, `border-radius`, `transform`, and `opacity` to create and animate icons purely from HTML `<span>` elements.

## The Sun Icon

The sun consists of two parts:
1. **A circular core** (the sun body)
2. **8 radiating rays** positioned around the core

### HTML Structure

```html
<span class="theme__icon">
    <span class="theme__icon-part"></span>  <!-- Core -->
    <span class="theme__icon-part"></span>  <!-- Ray 1 (0°) -->
    <span class="theme__icon-part"></span>  <!-- Ray 2 (45°) -->
    <span class="theme__icon-part"></span>  <!-- Ray 3 (90°) -->
    <span class="theme__icon-part"></span>  <!-- Ray 4 (135°) -->
    <span class="theme__icon-part"></span>  <!-- Ray 5 (180°) -->
    <span class="theme__icon-part"></span>  <!-- Ray 6 (225°) -->
    <span class="theme__icon-part"></span>  <!-- Ray 7 (270°) -->
    <span class="theme__icon-part"></span>  <!-- Ray 8 (315°) -->
</span>
```

### CSS Breakdown

#### The Sun Core (First `theme__icon-part`)

```css
.theme__icon-part {
    border-radius: 50%;
    /* Creates inset shadow that looks like a filled circle */
    box-shadow: 0.3em -0.3em 0 0.4em hsl(0,0%,100%) inset;
    top: calc(50% - 0.4em);
    left: calc(50% - 0.4em);
    width: 0.8em;
    height: 0.8em;
    transform: scale(0.5);  /* Scaled down in sun mode */
}
```

**How it works:**
- `box-shadow: inset` creates a shadow inside the element
- The offset (`0.3em -0.3em`) and spread (`0.4em`) fill the circle with white
- `transform: scale(0.5)` makes it smaller when showing as sun

#### The Sun Rays (Remaining `theme__icon-part` elements)

```css
.theme__icon-part ~ .theme__icon-part {
    background-color: hsl(0,0%,100%);
    border-radius: 0.05em;  /* Slightly rounded rectangles */
    box-shadow: none;
    top: 50%;
    left: calc(50% - 0.04em);
    transform-origin: 50% 0;  /* Rotate from top center */
    width: 0.08em;
    height: 0.16em;
}
```

**Positioning each ray with rotation:**

```css
/* Each ray rotates around the center point */
.theme__icon-part:nth-child(2) { transform: rotate(0deg) translateY(0.4em); }
.theme__icon-part:nth-child(3) { transform: rotate(45deg) translateY(0.4em); }
.theme__icon-part:nth-child(4) { transform: rotate(90deg) translateY(0.4em); }
.theme__icon-part:nth-child(5) { transform: rotate(135deg) translateY(0.4em); }
.theme__icon-part:nth-child(6) { transform: rotate(180deg) translateY(0.4em); }
.theme__icon-part:nth-child(7) { transform: rotate(225deg) translateY(0.4em); }
.theme__icon-part:nth-child(8) { transform: rotate(270deg) translateY(0.4em); }
.theme__icon-part:nth-child(9) { transform: rotate(315deg) translateY(0.4em); }
```

**How it works:**
- Each ray is a small white rectangle
- `transform-origin: 50% 0` sets the rotation point at the top-center
- `rotate(Xdeg)` positions each ray at 45° intervals
- `translateY(0.4em)` pushes the ray outward from center

### Visual Representation

```
        Ray 1 (0°)
           |
   Ray 8   |   Ray 2
    (315°) | (45°)
        \  |  /
         \ | /
Ray 7 ----[●]---- Ray 3
(270°)   / | \    (90°)
        /  |  \
   Ray 6   |   Ray 4
   (225°)  |  (135°)
           |
        Ray 5 (180°)
```

## The Moon Icon

The moon is created by transforming the same elements:

### CSS for Moon State (when checked)

```css
.theme__toggle:checked ~ .theme__icon .theme__icon-part:nth-child(1) {
    /* Crescent moon effect using offset inset shadow */
    box-shadow: 0.15em -0.15em 0 0.15em hsl(0,0%,100%) inset;
    transform: scale(1);  /* Full size */
}

.theme__toggle:checked ~ .theme__icon .theme__icon-part ~ .theme__icon-part {
    opacity: 0;  /* Hide all rays */
}
```

**How the crescent works:**
- The `box-shadow` offset (`0.15em -0.15em`) creates the crescent shape
- Smaller spread (`0.15em`) vs sun's (`0.4em`) leaves a "bite" out of the circle
- `transform: scale(1)` enlarges the core to full size
- All rays fade out with `opacity: 0`

### Moon Shape Diagram

```
    ┌─────────┐
   ╱    ╲     │
  │      ╲    │  ← Shadow creates
  │       ╲   │    the dark area
  │      ╱    │
   ╲    ╱     │
    └─────────┘
```

## Animation

The transition between sun and moon is animated with CSS:

```css
.theme__icon-part {
    transition:
        box-shadow 0.3s ease-in-out,
        opacity 0.3s ease-in-out,
        transform 0.3s ease-in-out;
}
```

This creates smooth animations for:
- **box-shadow**: Morphs from sun core to crescent moon
- **opacity**: Fades rays in/out
- **transform**: Scales and repositions elements

## Complete Toggle Component

### Full HTML

```html
<label class="theme" title="Toggle theme">
    <span class="theme__toggle-wrap">
        <input id="theme-toggle" class="theme__toggle" type="checkbox" 
               role="switch" name="theme" value="dark">
        <span class="theme__icon">
            <span class="theme__icon-part"></span>
            <span class="theme__icon-part"></span>
            <span class="theme__icon-part"></span>
            <span class="theme__icon-part"></span>
            <span class="theme__icon-part"></span>
            <span class="theme__icon-part"></span>
            <span class="theme__icon-part"></span>
            <span class="theme__icon-part"></span>
            <span class="theme__icon-part"></span>
        </span>
    </span>
</label>
```

### Full CSS

```css
/* Theme Toggle Container */
.theme {
    display: flex;
    align-items: center;
    -webkit-tap-highlight-color: transparent;
    font-size: 14px;
}

/* Icon container and parts positioning */
.theme__icon,
.theme__toggle {
    z-index: 1;
}
.theme__icon,
.theme__icon-part {
    position: absolute;
}
.theme__icon {
    display: block;
    top: 0.25em;
    left: calc(0.25em - 1px);
    width: 1.2em;
    height: 1.2em;
    transition: transform 0.3s ease-in-out;
}

/* Sun core */
.theme__icon-part {
    border-radius: 50%;
    box-shadow: 0.3em -0.3em 0 0.4em hsl(0,0%,100%) inset;
    top: calc(50% - 0.4em);
    left: calc(50% - 0.4em);
    width: 0.8em;
    height: 0.8em;
    transition:
        box-shadow 0.3s ease-in-out,
        opacity 0.3s ease-in-out,
        transform 0.3s ease-in-out;
    transform: scale(0.5);
}

/* Sun rays */
.theme__icon-part ~ .theme__icon-part {
    background-color: hsl(0,0%,100%);
    border-radius: 0.05em;
    box-shadow: none;
    top: 50%;
    left: calc(50% - 0.04em);
    transform: rotate(0deg) translateY(0.4em);
    transform-origin: 50% 0;
    width: 0.08em;
    height: 0.16em;
}
.theme__icon-part:nth-child(3) { transform: rotate(45deg) translateY(0.4em); }
.theme__icon-part:nth-child(4) { transform: rotate(90deg) translateY(0.4em); }
.theme__icon-part:nth-child(5) { transform: rotate(135deg) translateY(0.4em); }
.theme__icon-part:nth-child(6) { transform: rotate(180deg) translateY(0.4em); }
.theme__icon-part:nth-child(7) { transform: rotate(225deg) translateY(0.4em); }
.theme__icon-part:nth-child(8) { transform: rotate(270deg) translateY(0.4em); }
.theme__icon-part:nth-child(9) { transform: rotate(315deg) translateY(0.4em); }

/* Toggle track */
.theme__toggle-wrap {
    position: relative;
    margin: 0;
}
.theme__toggle {
    background-color: hsl(48,90%,85%);
    border-radius: 25% / 50%;
    padding: 0.15em;
    width: 3.4em;
    height: 1.7em;
    border: none;
    -webkit-appearance: none;
    appearance: none;
    cursor: pointer;
    transition: background-color 0.3s ease-in-out;
}

/* Toggle ball */
.theme__toggle:before {
    background-color: hsl(48,90%,55%);
    border-radius: 50%;
    content: "";
    display: block;
    width: 1.4em;
    height: 1.4em;
    transition:
        background-color 0.3s ease-in-out,
        transform 0.3s ease-in-out;
}

/* Dark mode (checked) styles */
.theme__toggle:checked {
    background-color: hsl(223,50%,20%);
}
.theme__toggle:checked:before,
.theme__toggle:checked ~ .theme__icon {
    transform: translateX(1.7em);
}
.theme__toggle:checked:before {
    background-color: hsl(223,90%,55%);
}

/* Moon transformation */
.theme__toggle:checked ~ .theme__icon .theme__icon-part:nth-child(1) {
    box-shadow: 0.15em -0.15em 0 0.15em hsl(0,0%,100%) inset;
    transform: scale(1);
}
.theme__toggle:checked ~ .theme__icon .theme__icon-part ~ .theme__icon-part {
    opacity: 0;
}
```

## Key CSS Techniques Used

| Technique | Purpose |
|-----------|---------|
| `box-shadow: inset` | Creates filled shapes without background |
| `border-radius: 50%` | Makes circles from squares |
| `transform: rotate()` | Positions rays at angles |
| `transform: translateY()` | Pushes rays outward from center |
| `transform-origin` | Sets rotation pivot point |
| `opacity` | Fades rays in/out |
| `transition` | Animates property changes |
| `:checked` selector | Triggers dark mode styles |
| `~` sibling selector | Styles elements after checkbox |

## Advantages of CSS Icons

1. **No external files** - No SVG, PNG, or font files to load
2. **Scalable** - Uses `em` units, scales with font-size
3. **Themeable** - Colors can use CSS variables
4. **Animatable** - Smooth transitions between states
5. **Lightweight** - Just HTML spans and CSS
6. **Accessible** - Works with `role="switch"` and screen readers

## Browser Support

Works in all modern browsers:
- Chrome 60+
- Firefox 55+
- Safari 12+
- Edge 79+

## Credits

Based on the toggle design by Jon Kantner on CodePen.

---

*Last updated: February 2026*
