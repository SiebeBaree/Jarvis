import { describe, expect, it } from "vitest";
import { mealPrepDTO, type MealPrepRow } from "../src/lib/macros";

const row = (over: Partial<MealPrepRow> = {}): MealPrepRow =>
  ({
    id: "m1",
    userId: "u1",
    name: "Chicken rice",
    description: null,
    instructions: null,
    prepMinutes: 45,
    portions: 4,
    basis: "total",
    calories: 2400,
    proteinG: 200,
    carbsG: 240,
    fatG: 60,
    blobKey: null,
    blobUrl: null,
    contentType: null,
    sizeBytes: null,
    sortOrder: 0,
    createdAt: new Date(),
    updatedAt: new Date(),
    ...over,
  }) as MealPrepRow;

describe("macro basis", () => {
  it("divides batch totals across portions", () => {
    const dto = mealPrepDTO(row(), [], null);
    expect(dto.total.calories).toBe(2400);
    expect(dto.perPortion.calories).toBe(600);
    expect(dto.perPortion.proteinG).toBe(50);
  });

  it("multiplies up when the user entered per-portion numbers", () => {
    const dto = mealPrepDTO(row({ basis: "portion", calories: 600, proteinG: 50 }), [], null);
    expect(dto.perPortion.calories).toBe(600);
    expect(dto.total.calories).toBe(2400);
    expect(dto.total.proteinG).toBe(200);
  });

  it("keeps nulls null instead of turning them into zero", () => {
    const dto = mealPrepDTO(row({ calories: null, fatG: null }), [], null);
    expect(dto.total.calories).toBeNull();
    expect(dto.perPortion.calories).toBeNull();
    expect(dto.perPortion.proteinG).toBe(50);
  });

  it("never divides by zero when portions is somehow below one", () => {
    const dto = mealPrepDTO(row({ portions: 0 }), [], null);
    expect(dto.perPortion.calories).toBe(2400);
  });

  it("rounds to one decimal rather than showing 16.666666 g of fat", () => {
    const dto = mealPrepDTO(row({ portions: 3, fatG: 50 }), [], null);
    expect(dto.perPortion.fatG).toBe(16.7);
  });

  it("orders ingredients by sortOrder regardless of row order", () => {
    const dto = mealPrepDTO(
      row(),
      [
        { id: "b", userId: "u1", mealPrepId: "m1", name: "Rice", quantity: "500 g", sortOrder: 1 },
        { id: "a", userId: "u1", mealPrepId: "m1", name: "Chicken", quantity: "1 kg", sortOrder: 0 },
      ],
      null,
    );
    expect(dto.ingredients.map((i) => i.name)).toEqual(["Chicken", "Rice"]);
  });

  it("reports whether a photo exists", () => {
    expect(mealPrepDTO(row(), [], null).hasPhoto).toBe(false);
    expect(mealPrepDTO(row({ blobKey: "meals/x.jpg" }), [], "https://signed").hasPhoto).toBe(true);
  });
});
