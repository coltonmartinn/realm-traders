--!strict
-- Redeemable promo codes (post them in update notes, socials, the group...).
-- Server-only so clients can't read the list. Codes are case-insensitive.
-- Retire a code by deleting it; players who redeemed it keep the reward.

return {
	RELEASE = 500,
	MARKET = 250,
	TRADER = 250,
} :: { [string]: number }
