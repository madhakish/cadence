# Plate and bar rendering reference spec (researched 2026-09-26)

## Evidence key
- **V** = verified this session: page or PDF fetched with curl, value read in the text.
- **G** = Gemini (agy) quoted it from the page, not re-fetched by me.
- **unverified** = Gemini gave it with no deep URL, or I inferred it. Treat as a placeholder.

## Primary sources
- [IWF] IWF TCRR 2025, as of 05 Nov 2025. The live site returns 403, so this is a Wayback copy: https://web.archive.org/web/20251128000353id_/https://iwf.sport/wp-content/uploads/downloads/2025/11/IWF-TCRR-2025-as-of-05-November-2025.pdf (original: https://iwf.sport/wp-content/uploads/downloads/2025/11/IWF-TCRR-2025-as-of-05-November-2025.pdf). **V**
- [IPF] IPF Technical Rulebook, effective 01 Mar 2026: https://www.powerlifting.sport/fileadmin/ipf/data/rules/technical-rules/english/2026_IPF_Technical_Rulebook__effective_01_March_2026__v3.pdf **V**

## Colour hex values (all sets)
**All hex values in this document are unverified.** Gemini estimated them. Nobody sampled them from real photos. Sample them from the photo references (last section) before using them.

| Colour | Matte rubber (IWF bumpers) | Gloss painted steel (calibrated) |
|---|---|---|
| Red | #C83232 | #B22222 |
| Blue | #285A96 | #1C39BB |
| Yellow | #D2B428 | #FFD700 (too saturated for a photo, probably) |
| Green | #28783C | #006400 |
| White | #E6E6E6 | #F0F0F0 |
| Black | n/a | #1A1A1A |
| Chrome/silver | n/a | #C0C0C0 base; render as metal, not a flat colour |

---

## 1. IWF competition bumpers (kg)

### Rules (IWF TCRR 2025, Appendix "Competition discs" and clause 3.3.3.6) **V**
- **Colours:** 25 red, 20 blue, 15 yellow, 10 green, 5 white. Change plates: 2.5 red, 2 blue, 1.5 yellow, 1 green, 0.5 white.
- **Training discs:** may be black with coloured rims, marked "Training".
- **Material:** discs of 10 kg and up are covered in rubber or plastic, with permanent colour on both sides. Discs under 10 kg may be metal.
- **Marking:** weight in kg, required on every disc.

| Denom | IWF max width | IWF diameter | Eleiko IWF thickness | Rogue KG Comp thickness | Rogue KG change plate (dia / thick) | Colour |
|---|---|---|---|---|---|---|
| 25 kg | 67 mm [IWF] | 450 ±1 mm [IWF] | 58 mm (G) [E25] | **66 mm (V)** [RKC]; other figure: 64 mm (unverified, Gemini pass 1) | – | red |
| 20 kg | 54 mm | 450 ±1 mm | 50 mm (G) | **55 mm (V)**; other: 54 mm (unverified) | – | blue |
| 15 kg | 43 mm | 450 ±1 mm | 39 mm (G) | **42 mm (V)**; other: 44 mm (unverified) | – | yellow |
| 10 kg | 35 mm | 450 ±1 mm | 35 mm (G) | **29 mm (V)**; other: 32 mm (unverified) | – | green |
| 5 kg | 26.5 mm | 230–260 mm | unverified | – | 230 / 26 mm (V) [RKCP] | white |
| 2.5 kg | 23 mm | 190–220 mm | unverified | – | 210 / 19 mm (V) | red |
| 2 kg | 22 mm | 155–193 mm | unverified | – | 190 / 19 mm (V) | blue |
| 1.5 kg | 20 mm | 139–175 mm | unverified | – | 175 / 18 mm (V) | yellow |
| 1 kg | 19 mm | 118–160 mm | unverified | – | 160 / 15 mm (V) | green |
| 0.5 kg | 16 mm | 97–137 mm | unverified | – | 135 / 12.5 mm (V) | white |

Rogue's 66 mm for 25 kg is within the IWF 67 mm maximum. The 64/54/44/32 set came from Gemini pass 1 with no deep source. The Rogue page contradicts it, so prefer 66/55/42/29.

Brands not in the table (all unverified, Gemini cited only site homepages):
- **Uesaka:** 25 kg 61.36, 20 kg 52.95, 15 kg 43.69, 10 kg 36.80 mm.
- **ZKC:** 20 kg 45 mm. Change plates: 2 kg 190/20, 1.5 kg 175/19, 1 kg 155/17 mm.

**Construction and finish**
- **Hub (Rogue):** 50.4 mm collar opening. **V** [RKC]
- **Rogue face:** gloss-matte-gloss colour finish. Lettering is raised, with the Rogue brand and IWF logo in white. **V** [RKC]
- **Rogue centre:** a raised rubber surface keeps the steel centre discs from touching. Plates meet only at the inner and outer flanges. **V** [RKC]
- **Rogue rim:** has a lip for pickup. **V** [RKC]
- **Rogue change plates:** Rogue logo above and below the hole, IWF logo on the back. **V** [RKCP]
- **Hub bolt count and pattern:** unverified for every brand. Photos show a bolted steel centre disc; check the count against the photos.

---

## 2. IPF calibrated steel (kg)

### Rules (IPF Technical Rulebook 2026, section 2.3(b)) **V**
- **Colours:** the IPF mandates colour for 25 red, 20 blue, 15 yellow. For **10 kg and under it says "any color".** The 10 green / 5 white / 2.5 black / 1.25 chrome scheme is industry convention only; the IPF does not require it. Gemini pass 1 said otherwise and was wrong.
- **Largest disc diameter:** 450 mm or less.
- **Centre hole:** 52–53 mm.
- **Thickness:** discs of 20 kg and over may be at most 60 mm. Discs of 15 kg and under may be at most 30 mm.
- **Allowed denominations:** 1.25–25 kg. For records, 0.25/0.5/1/1.5 kg discs are also allowed.
- **Tolerance:** ±0.25% or ±10 g.
- **Marking:** weight clearly marked on every disc.
- **Loading:** the first, heaviest disc goes on face-in; the rest go face-out.

| Denom | Rogue Calibrated KG diameter (V) [RCAL] | Rogue thickness | Eleiko IPF (dia / thick) | Conventional colour |
|---|---|---|---|---|
| 50 kg | 450 mm | unverified | – | (not IPF) |
| 25 kg | 450 mm | unverified | 450 / 27 mm (unverified, no deep URL) | red |
| 20 kg | 450 mm | 22.5 mm (unverified) | unverified | blue |
| 15 kg | 400 mm | 21 mm (unverified) | unverified | yellow |
| 10 kg | 325 mm | 21 mm (unverified) | unverified | green (convention) |
| 5 kg | 228 mm | 21.5 mm (unverified) | unverified | white (convention) |
| 2.5 kg | 190 mm | 16 mm (unverified) | unverified | black (convention) |
| 1.25 kg | 160 mm | 12 mm (unverified) | unverified | chrome (convention) |
| 0.5 kg | 134 mm | 8 mm (unverified) | – | chrome (convention) |
| 0.25 kg | 112 mm | 6 mm (unverified) | – | chrome (convention) |

Gemini pass 1 marked the Rogue sub-450 diameters as "INFERRED". The Rogue page table confirms them all. Rogue shows its thicknesses only in an image, so none of them are verified.

**Construction and finish (Rogue) V [RCAL]**
- **Finish:** medium-gloss powder coat. The back, sides and raised surfaces are precision-machined.
- **Hole:** 50.4 mm centre hole.
- **Calibration:** plugs on the back.
- **Lettering:** bold white text. Artwork on one side only.
- **Chrome and black variants:** exist, but were not fetched.
- **York calibrated IPF plates:** no data (unverified).

---

## 3. lb colour bumpers

- **Standard?** The IWF colour rule is kg only. The lb scheme (55 red, 45 blue, 35 yellow, 25 green, 10 white or black) is brand convention. unverified: I found no standards document.

| Denom | Rogue Color Echo width (V) [ECHO] | Diameter | Colour |
|---|---|---|---|
| 55 lb | 2.75 in (69.9 mm) | 450 mm ±3 (V) | red (unverified) |
| 45 lb | 2.36 in (59.9 mm) | 450 mm | blue (unverified) |
| 35 lb | 1.93 in (49.0 mm) | 450 mm | yellow (unverified) |
| 25 lb | 1.50 in (38.1 mm) | 450 mm | green (unverified) |
| 15 lb | 1.04 in (26.4 mm) | 450 mm | unverified (Gemini: black with coloured stripe) |
| 10 lb | 0.83 in (21.1 mm) | 450 mm | unverified |

- **Discrepancy:** Gemini pass 1 gave 2.40 / 1.90 in for the 45 / 35 lb Echo. The page says 2.36 / 1.93 in, so use the page figures.
- **Echo construction:** 50.4 mm collar opening. Stainless steel insert with virgin rubber. **V** [ECHO]
- **Rogue LB Competition plates:** unverified. The URL tried returned 404. Gemini pass 1 guessed 55 / 45 / 35 / 25 lb = 2.15 / 1.90 / 1.70 / 1.25 in. Those numbers are unverified.

**Rogue LB change plates (V) [RLBC]**

| Denom | Diameter | Width | Colour |
|---|---|---|---|
| 10 lb | 230 mm | 26 mm | white |
| 5 lb | 190 mm | 19 mm | blue |
| 2.5 lb | 162 mm | 15 mm | green |
| 1.25 lb | 133.3 mm | 10 mm | white |

- Rubber-coated metal centre with a matte finish. Rogue logo above and below the hole, back blank. **V**
- These colours are Rogue's own. There is no lb change-plate standard.

**Rogue Calibrated LB steel diameters (V) [RCALB]**

| Denom | Diameter |
|---|---|
| 55 lb | 450 mm |
| 45 lb | 450 mm |
| 35 lb | 400 mm |
| 25 lb | 325 mm |
| 10 lb | 228 mm |
| 5 lb | 190 mm |
| 2.5 lb | 160 mm |
| 1 lb | 134 mm |
| 0.5 lb | 112 mm |
| 0.25 lb | 90 mm |

Thicknesses: unverified. Finish: same medium-gloss powder coat as the kg plates. **V**

---

## 4. lb cast iron and machined steel

| Denom | Rogue Deep Dish (dia / thick) (V) [DD] | Rogue Machined (dia / width) (V) [MACH] | York Legacy (dia / thick) (unverified) [YORK] |
|---|---|---|---|
| 100 lb | 450 / 75 mm | – | – |
| 45 lb | 450 / 50 mm | 448 mm / 1.50 in | 17.5 / 1.5 in |
| 35 lb | 360 / 34.5 mm | 360 mm / 1.50 in | 14.875 / 1.37 in |
| 25 lb | 276 / 34.5 mm | 300 mm / 1.50 in | 12 / 1.25 in |
| 10 lb | 229 / 20 mm | 228 mm / 1.22 in | 9.125 / 1 in |
| 5 lb | 190 / 14.5 mm | 195 mm / 0.83 in (unverified) | 7.5 / 0.75 in |
| 2.5 lb | – | 162 mm / 0.63 in (unverified) | 6.5 / 0.44 in |

- **Rogue Deep Dish:** black e-coat finish, ductile iron. The 5 lb change plate is Class 30 grey iron. **V**
- **Rogue Machined:** grey hammertone finish with raised black text. **V**
- **Rogue 25 lb diameters differ:** Deep Dish 276 mm, Machined 300 mm. Both are verified; they are different products.
- **Gemini pass 1 errors on Deep Dish:** it gave 45 lb as 1.97 in, which matches the page's 50 mm. It gave 35 and 25 lb as 1.35 in, which also matches.
- **York:** Gemini cited the York Legacy product page, but I did not re-fetch it. Treat the York values as unverified.
- **Ivanko:** no data.
- **Machined chrome hub ring, lb marking style:** unverified. Check against the photos.

---

## 5. Bars and collars

### IWF bars (TCRR 2025 appendix) **V** [IWF]

| | Men's 20 kg | Women's 15 kg |
|---|---|---|
| Length | 2200 mm | 2010 mm |
| Grip section | 28 mm diameter, 1310 mm long | 25 mm diameter, 1310 mm long |
| Sleeves | 50 mm diameter, 415 mm long | 50 mm diameter, 320 mm long |
| Rim (inner collar) diameter | 73–85 mm | 63–80 mm |
| Knurl | Two grip sections of 445 mm, each with a non-knurled 5 mm strip 195 mm from the inner sleeve | Two grip sections spaced 420 mm apart, same 5 mm strip at 195 mm |
| Centre knurl | 120 mm | none specified |
| Identification marking | blue, at each end and the centre | yellow, at each end and the centre |
| Material | chromed steel | chromed steel |
| Tolerance | +0.1% / −0.05% | +0.1% / −0.05% |

- **Mark spacing:** the TCRR does not state it. I derived it: 1310 − 2 × (195 + 2.5) = 915 mm between strip centres. This matches the commonly quoted "910 mm" (unverified).

### IPF bar (2026 rulebook) **V** [IPF]
- Length: 2.2 m maximum.
- Distance between collar faces: 1310–1320 mm.
- Shaft: 28–29 mm.
- Sleeves: 50–52 mm.
- **Machined marks:** 810 mm apart.
- **No chrome on the knurling.**
- Bar plus collars: 25 kg.
- The knurl guideline diagram lists 120 mm (centre knurl), plus 160, 240, 245 and 440 mm.

### Collars
- **IWF:** two per bar, 2.5 kg each. Chromed steel, 50 mm hole, 70 mm maximum width, +10 / −0 g. **V** [IWF]
- **IPF:** 2.5 kg each. **V** [IPF]
- **Look:** a machined chrome ring with a lever or screw clamp. The look is unverified; the Eleiko and Rogue collar pages were not fetched.

### Sleeve finishes (appearance only; unverified descriptive text from Gemini)
- **Hard chrome:** bright mirror.
- **Bright zinc:** silver with a slight blue tint, less reflective than chrome.
- **Stainless steel:** satin silver.
- **Cerakote:** matte ceramic, coloured.
- **Black oxide:** flat dark grey-black.

---

## 6. Photo references (visual reference only)

- **Eleiko IWF**
  - Product page: https://eleiko.com/en-se/equipment/plates/weightlifting/3085231-25-eleiko-iwf-weightlifting-competition-plate-25-kg
  - Images (Gemini-extracted, not checked):
    - https://media.eleiko.com/images/upload/4x5/3085231-25_10.jpg
    - https://media.eleiko.com/images/upload/15ZTLGKKB6_xs2.jpg
    - https://media.eleiko.com/images/upload/V4PGUWIYFU_normal.jpg
- **Eleiko IPF**
  - Category page (G): https://eleiko.com/en-us/equipment/plates/powerlifting-plates
- **Rogue KG Competition (IWF):** https://www.roguefitness.com/rogue-kg-competition-plates (V)
- **Rogue KG Change Plates:** https://www.roguefitness.com/rogue-kg-change-plates (V)
- **Rogue Calibrated KG**
  - Product page: https://www.roguefitness.com/rogue-calibrated-kg-steel-plates (V)
  - Images (Gemini-extracted, not checked):
    - https://assets.roguefitness.com/f_auto,q_auto,c_limit,w_1600,b_rgb:ffffff/v1/catalog/Weightlifting%20Bars%20and%20Plates/Plates/Steel%20Plates/IP0547-Color/IP0547-Color-H_uto7no.png
    - https://assets.roguefitness.com/f_auto,q_auto,c_limit,w_1600,b_rgb:ffffff/v1/catalog/Weightlifting%20Bars%20and%20Plates/Plates/Steel%20Plates/IP0547-Color/IP0547-KG-Color-web2_yvrj1q.png
- **Rogue Calibrated LB:** https://www.roguefitness.com/rogue-calibrated-lb-steel-plates (V)
- **Rogue Color Echo**
  - Product page: https://www.roguefitness.com/rogue-color-echo-bumper-plate (V)
  - Images (Gemini-extracted, not checked):
    - https://assets.roguefitness.com/f_auto,q_auto,c_limit,w_1600,b_rgb:ffffff/v1/catalog/Weightlifting%20Bars%20and%20Plates/Plates/Bumper%20Plates/IP0119/IP0119-WEB1_s6lvrr.png
    - https://assets.roguefitness.com/f_auto,q_auto,c_limit,w_1600,b_rgb:ffffff/v1/catalog/Weightlifting%20Bars%20and%20Plates/Plates/Bumper%20Plates/IP0119/IP0119-WEB2_ouinci.png
- **Rogue LB Change Plates:** https://www.roguefitness.com/rogue-lb-change-plates (V)
- **Rogue Deep Dish:** https://www.roguefitness.com/rogue-deep-dish-plates (V)
- **Rogue Machined:** https://www.roguefitness.com/rogue-machined-olympic-plates (V)
- **York iron**
  - Legacy page (not fetched): https://yorkbarbell.com/product/2-legacy-cast-iron-precision-milled-olympic-plate/
  - No direct images found.

## Source keys
- [E25]: Eleiko 25 kg IWF page, above.
- [RKC]: rogue-kg-competition-plates.
- [RKCP]: rogue-kg-change-plates.
- [RCAL]: rogue-calibrated-kg-steel-plates.
- [RCALB]: rogue-calibrated-lb-steel-plates.
- [ECHO]: rogue-color-echo-bumper-plate.
- [RLBC]: rogue-lb-change-plates.
- [DD]: rogue-deep-dish-plates.
- [MACH]: rogue-machined-olympic-plates.
- [YORK]: York Legacy page, above.
- All Rogue keys are at https://www.roguefitness.com/<slug>.

## Open gaps
- **Hex:** all hex values need sampling from photos.
- **Rogue and Eleiko:** calibrated thicknesses; Eleiko IWF change-plate and IPF dimensions.
- **Other brands:** York and Ivanko specs; Uesaka and ZKC deep sources.
- **Construction and appearance:** hub bolt patterns, collar appearance, Color Echo colour-by-weight mapping.
- **Image URLs:** existence of the Gemini-extracted image URLs.
