# Shopper scans shop QR codes

- Earn: `https://villagerewards.com.au/app.html?shop=SHOP_ID`
- Redeem: `https://villagerewards.com.au/app.html?redeem=SHOP_ID`
- Both preserve the shop intent through customer registration/returning access.
- Earn checks the four-hour customer/shop check-in cooldown, inserts a purchase with amount=0, points=1 and note=qr_scan and shows shopper success. These counter QR links do not require GPS. Legacy `?checkin=SHOP_ID` retains its previous GPS/DEV_MODE behaviour.
- Redeem shows active stamp rewards for this shop and the customer's progress. Explicit confirmation calls `redeem_shop_stamp`; eligibility, monthly limits, history and card reset use the existing redemption functions. No village balance is spent for a shop stamp reward.
- Shop cards and passport stamps count QR purchases without a minimum spend. Ordinary purchases retain their minimum-spend rules. GPS/staff check-ins record visits only, with zero stamps and no passport entry. Apply 202610290004_distinguish_qr_and_gps.sql alongside this update.
- Admin → Shops → Shop QR codes lists all active shops. Print opens a separate page, one A5 portrait counter card per shop, with both codes. Use the print page's button to print or save PDF.

Production prerequisite: `supabase/migrations/202610290002_shopper_stamp_redemption.sql` (applied to village-rewards on 29 October 2026). It keeps PIN values server-side and uses a customer-row lock around creation and validation.

This continues the existing pilot customer-ID access model, not verified customer authentication. Shopper completion without trader PIN was explicitly approved. Local fixtures and SQL tests do not certify production identity or multi-session behaviour. No production stamps or rewards were created during verification.
