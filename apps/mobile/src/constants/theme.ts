/**
 * Below are the colors that are used in the app. The colors are defined in the light and dark mode.
 * There are many other ways to style your app. For example, [Nativewind](https://www.nativewind.dev/), [Tamagui](https://tamagui.dev/), [unistyles](https://reactnativeunistyles.vercel.app), etc.
 */

import '@/global.css';

import { Platform } from 'react-native';

export const Colors = {
  light: {
    text: '#000000',
    background: '#ffffff',
    backgroundElement: '#F0F0F3',
    backgroundSelected: '#E0E1E6',
    textSecondary: '#60646C',
  },
  dark: {
    text: '#ffffff',
    background: '#000000',
    backgroundElement: '#212225',
    backgroundSelected: '#2E3135',
    textSecondary: '#B0B4BA',
  },
} as const;

export type ThemeColor = keyof typeof Colors.light & keyof typeof Colors.dark;

export const Fonts = Platform.select({
  ios: {
    /** iOS `UIFontDescriptorSystemDesignDefault` */
    sans: 'system-ui',
    /** iOS `UIFontDescriptorSystemDesignSerif` */
    serif: 'ui-serif',
    /** iOS `UIFontDescriptorSystemDesignRounded` */
    rounded: 'ui-rounded',
    /** iOS `UIFontDescriptorSystemDesignMonospaced` */
    mono: 'ui-monospace',
  },
  default: {
    sans: 'normal',
    serif: 'serif',
    rounded: 'normal',
    mono: 'monospace',
  },
  web: {
    sans: 'var(--font-display)',
    serif: 'var(--font-serif)',
    rounded: 'var(--font-rounded)',
    mono: 'var(--font-mono)',
  },
});

export const Spacing = {
  half: 2,
  one: 4,
  two: 8,
  three: 16,
  four: 24,
  five: 32,
  six: 64,
} as const;

export const BottomTabInset = Platform.select({ ios: 50, android: 80 }) ?? 0;
export const MaxContentWidth = 800;

/**
 * Score bands map a 0–100 score onto a semantic color. Each band carries a
 * light- and dark-scheme color tuned to feel native alongside the base palette.
 */
export const ScoreBands = {
  slate: {
    light: '#8A8F98',
    dark: '#9BA1AA',
  },
  amber: {
    light: '#E5960B',
    dark: '#F5B841',
  },
  green: {
    light: '#2CA24C',
    dark: '#4CD268',
  },
  gold: {
    light: '#C79A1E',
    dark: '#E9C558',
  },
} as const;

export type ScoreBand = keyof typeof ScoreBands;

/** Returns the band key for a score. Scores are clamped to the 0–100 range. */
export function scoreBand(score: number): ScoreBand {
  if (score >= 90) return 'gold';
  if (score >= 70) return 'green';
  if (score >= 50) return 'amber';
  return 'slate';
}

/**
 * Area colors give each life area a distinct, harmonized hue with light- and
 * dark-scheme variants.
 */
export const AreaColors = {
  business: {
    light: '#3B5BDB',
    dark: '#6E8BFF',
  },
  social: {
    light: '#F06543',
    dark: '#FF8462',
  },
  physical: {
    light: '#1B9E77',
    dark: '#3FCFA0',
  },
} as const;

export type Area = keyof typeof AreaColors;
