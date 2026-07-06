import { z } from "zod";

export const AREAS = ["business", "social", "physical"] as const;

export type Area = (typeof AREAS)[number];

export const AreaSchema = z.enum(AREAS);
