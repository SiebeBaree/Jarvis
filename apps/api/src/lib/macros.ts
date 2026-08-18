// Meal-prep macro arithmetic and DTO shaping. Database-free on purpose, so the
// per-portion / whole-batch conversion — the one place this feature can quietly
// lie to the user — is unit-tested in isolation.

import type { mealPrepIngredients, mealPreps } from "@/db/schema";

export type MealPrepRow = typeof mealPreps.$inferSelect;
export type IngredientRow = typeof mealPrepIngredients.$inferSelect;

export interface IngredientDTO {
  id: string;
  name: string;
  quantity: string | null;
  sortOrder: number;
}

export interface MacrosDTO {
  calories: number | null;
  proteinG: number | null;
  carbsG: number | null;
  fatG: number | null;
}

export interface MealPrepDTO {
  id: string;
  name: string;
  description: string | null;
  instructions: string | null;
  prepMinutes: number | null;
  portions: number;
  /** Which of the two macro blocks below the user actually typed in. */
  basis: "portion" | "total";
  perPortion: MacrosDTO;
  total: MacrosDTO;
  photoUrl: string | null;
  hasPhoto: boolean;
  ingredients: IngredientDTO[];
  sortOrder: number;
  createdAt: Date;
  updatedAt: Date;
}

function scaleMacros(row: MealPrepRow, factor: number): MacrosDTO {
  const scale = (value: number | null) =>
    value === null ? null : Math.round(value * factor * 10) / 10;
  return {
    calories: scale(row.calories),
    proteinG: scale(row.proteinG),
    carbsG: scale(row.carbsG),
    fatG: scale(row.fatG),
  };
}

/**
 * Both views of the macros, always. The user entered one of them; deriving the
 * other server-side means the app never has to know the division rule, and a
 * portions edit can never leave the two disagreeing.
 */
export function mealPrepDTO(
  row: MealPrepRow,
  ingredients: IngredientRow[],
  photoUrl: string | null,
): MealPrepDTO {
  const portions = Math.max(1, row.portions);
  const perPortion = row.basis === "portion" ? scaleMacros(row, 1) : scaleMacros(row, 1 / portions);
  const total = row.basis === "total" ? scaleMacros(row, 1) : scaleMacros(row, portions);

  return {
    id: row.id,
    name: row.name,
    description: row.description,
    instructions: row.instructions,
    prepMinutes: row.prepMinutes,
    portions: row.portions,
    basis: row.basis,
    perPortion,
    total,
    photoUrl,
    hasPhoto: row.blobKey !== null,
    ingredients: ingredients
      .slice()
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map((item) => ({
        id: item.id,
        name: item.name,
        quantity: item.quantity,
        sortOrder: item.sortOrder,
      })),
    sortOrder: row.sortOrder,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  };
}
