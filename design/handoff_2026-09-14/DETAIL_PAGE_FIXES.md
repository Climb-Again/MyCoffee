# Detail page — fix list

Against the build screenshot of *Gasharu* (Sep 2026). Numbered by severity. Same rules as `UPDATE_BRIEF.md`: no substitutions, leave a `// DEVIATION:` comment if something is genuinely impossible.

---

## 1. The roaster rail renders twice

"More from DAK Coffee Roasters" appears twice — once complete, then again below, clipped behind the tab bar with a second row of cards.

**Build instead:** one rail, once. The duplicate is almost certainly the section being emitted inside both the scroll content and a footer, or a `ForEach` over a list that already contains the group.

**Acceptance:** scrolling to the bottom of the page shows exactly one "More from …" heading.

---

## 2. Rail cards are clipped

Card ratings are cut in half by the container ("4.9" is sliced). The rail also runs under the floating tab bar with no bottom inset.

**Build instead:** size the rail to its content — thumb, title, rating, all fully visible — and add bottom content inset equal to the tab bar height plus 16 so the last row clears it.

**Acceptance:** every rail card's rating digit is fully visible, and the last item scrolls clear of the tab bar.

---

## 3. Stars don't reflect the score

4.1 shows five solid stars. That reads as 5.0.

**Build instead:** four filled and a partial fifth (mask the fifth to 10%), or four filled plus one outline. Stars stay the accent blue; size them so the row is optically level with the numeral's baseline, not its cap height.

**Acceptance:** a 4.1 and a 5.0 are distinguishable at a glance.

---

## 4. Favourite button is a blue blob

The active heart sits on a filled blue shape that isn't a circle — it looks like a rendering artefact of a rounded rect fighting a capsule mask, and it's visually much heavier than share and edit beside it.

**Build instead:** the three hero buttons are identical circles in the same glass capsule, all three tinted the same. Favourite state is carried by the **icon** only — `heart` outline when off, `heart-fill` when on. No filled background, no colour change on the button itself.

**Acceptance:** the three buttons are the same size, same shape, same background; only the heart's fill differs between states.

---

## 5. Value meter pills are all lit

Five dots, all blue, next to GREAT VALUE. The meter is meant to *show* the position — all-on carries no information and can't distinguish GREAT from FAIR.

**Build instead:** five pills, the lit count set by the verdict (GREAT VALUE 5, FAIR VALUE 3, OVERPAID 1–2); unlit pills at 15% of the accent. Same pill geometry as the coffees row so the two read as one system.

**Acceptance:** a FAIR VALUE coffee and a GREAT VALUE coffee show a different number of lit pills.

---

## 6. Dead space above "Full text", and the label is wrong

There is roughly a screen-tenth of empty space between the Farm row and the link, and "Full text" doesn't say what text.

**Build instead:** collapse the gap to the standard section spacing (24). Label the row **From the roaster** — that is what the brief specifies and what the content is. Keep `chevron-right` as the disclosure.

**Acceptance:** no gap larger than 24 between the purchase facts and the following row; the row reads "From the roaster".

---

## 7. Missing sections

The brief's detail page also carries a **review pill** next to the rating and a **brew guide** block. Neither is present.

**Build instead:** add both per §7–8 of the brief. If the data isn't there yet, omit the section entirely rather than showing an empty shell — and say so in the PR.

---

## 8. Tab bar is still a custom capsule

A floating rounded pill with a tinted chip behind the selected tab. This is the §3 mistake again: the native tab bar is already glass and already indicates selection.

**Build instead:** a plain `TabView` with three `Tab`s. No background, no overlay, no selection capsule, no `.ignoresSafeArea`.

**Acceptance:** the tab bar is the system tab bar; content blurs under it while scrolling.

---

## 9. Hero, minor

- The expand/fullscreen button in the hero's bottom-right corner isn't in the design — remove it, or tap-to-zoom the photo instead.
- The previous screen's text is visible above the hero during the push transition. Extend the hero image to the top edge so nothing shows through under the status bar.
