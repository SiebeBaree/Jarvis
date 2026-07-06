import { z } from "zod";

/** `"HH:MM"` 24-hour time string, e.g. `"03:00"` or `"23:59"`. */
const HhMm = z
  .string()
  .regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Expected HH:MM (24-hour) time");

export const SettingsSchema = z.object({
  timezone: z.string().min(1),
  dayEndsAt: HhMm,
  expoPushToken: z.string().nullable(),
  morningBriefingAt: HhMm.nullable(),
  eveningReviewAt: HhMm.nullable(),
  coachModel: z.string().min(1),
});

export const SettingsPatchSchema = SettingsSchema.partial();

export type Settings = z.infer<typeof SettingsSchema>;
export type SettingsPatch = z.infer<typeof SettingsPatchSchema>;
