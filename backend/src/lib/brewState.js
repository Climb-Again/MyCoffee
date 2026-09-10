// Pure brew-trial state machine (PLAN.md §14, backlog #155). No DB, no network
// — routes/brew.js consumes these and turns the returned descriptions into SQL
// inside one transaction, and the whole thing is unit-testable with zero DB.
//
// A (coffee, option) pair is tri-state: untried (no row) / tried / best. There
// is at most one `best` per (coffee, kind) — a DB partial unique index enforces
// it, and setting a new best demotes the previous best of that kind in the same
// transaction (`best ⇒ tried`).

/**
 * Describe the row mutations that move a (coffee, option) pair to `state`.
 *
 * @param {{ bestOptionId: (number|null) }} current  the coffee's current winner
 *        for this option's kind (null when there is none). Used to demote the
 *        prior best when a new one is set.
 * @param {{ id: number, kind: string }} option      the option being changed.
 * @param {'untried'|'tried'|'best'} state           the target tri-state.
 * @returns {{ mutations: Array<object> }}  ordered mutation descriptions:
 *   - { action: 'delete',  optionId }                     (untried)
 *   - { action: 'demote',  optionId, kind }               (best: prior winner → tried)
 *   - { action: 'upsert',  optionId, kind, isBest }       (tried / best)
 *   Ordered demote-before-upsert so the one-best-per-kind index never sees two.
 */
export function nextTrialRows(current, option, state) {
  if (state === 'untried') {
    return { mutations: [{ action: 'delete', optionId: option.id }] };
  }

  const isBest = state === 'best';
  const mutations = [];

  // Demote the existing winner of this kind first, so upserting the new best
  // never collides with the partial unique index on (coffee_id, kind).
  const priorBest = current?.bestOptionId ?? null;
  if (isBest && priorBest != null && priorBest !== option.id) {
    mutations.push({ action: 'demote', optionId: priorBest, kind: option.kind });
  }

  mutations.push({ action: 'upsert', optionId: option.id, kind: option.kind, isBest });
  return { mutations };
}

/**
 * The grind + temp `tried` rows a recipe implies. A recipe pins a nominal grind
 * and temperature, and "I tried the 4:6 recipe" *is* trying its clicks at its
 * temperature — so setting a recipe tried/best also ticks the matching grind
 * and temp options (never `best`, one-way). Returns the numeric options to
 * get-or-create and tick.
 *
 * @param {{ kind: string, grindClicks: (number|null), waterTempC: (number|null) }} recipeOption
 * @returns {Array<{ kind: 'grind'|'temp', valueNum: number, state: 'tried' }>}
 */
export function impliedTrials(recipeOption) {
  if (!recipeOption || recipeOption.kind !== 'recipe') return [];

  const trials = [];
  const grind = recipeOption.grindClicks;
  const temp = recipeOption.waterTempC;
  if (grind != null) trials.push({ kind: 'grind', valueNum: Number(grind), state: 'tried' });
  if (temp != null) trials.push({ kind: 'temp', valueNum: Number(temp), state: 'tried' });
  return trials;
}
