# Shopper scans shop QR codes

- Earn: `https://villagerewards.com.au/app.html?shop=SHOP_ID`
- Redeem: `https://villagerewards.com.au/app.html?redeem=SHOP_ID`
- Both preserve the shop intent through customer registration/returning access.
- Earn checks the four-hour customer/shop check-in cooldown, inserts one check-in stamp and shows shopper success. These counter QR links do not require GPS. Legacy `?checkin=SHOP_ID` retains its previous GPS/DEV_MODE behaviour.
- Redeem shows active stamp rewards for this shop and the customer's progress. Explicit confirmation calls `redeem_shop_stamp`; eligibility, monthly limits, history and card reset use the existing redemption functions. No village balance is spent for a shop stamp reward.
- Shop cards now count both QR check-in stamps and purchases that meet the reward's minimum spend. The passport campaign is separate; its existing purchase/minimum-spend rules are unchanged.
- Admin → Shops → Shop QR codes lists all active shops. Print opens a separate page, one A5 portrait counter card per shop, with both codes. Use the print page's button to print or save PDF.

Production prerequisite: `supabase/migrations/202610290002_shopper_stamp_redemption.sql` (applied to village-rewards on 29 October 2026). It keeps PIN values server-side and uses a customer-row lock around creation and validation.

This continues the existing pilot customer-ID access model, not verified customer authentication. Shopper completion without trader PIN was explicitly approved. Local fixtures and SQL tests do not certify production identity or multi-session behaviour. No production stamps or rewards were created during verification.
