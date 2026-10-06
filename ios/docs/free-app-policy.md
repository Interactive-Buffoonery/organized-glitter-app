# Free native app policy

Effective October 5, 2026. This decision replaces earlier native tip and
purchase planning, including the native portions of the tips-first ADR.

## Product contract

- The iPhone and iPad app is free to download and use. All native features,
  including planned catalog access and contributions, are free.
- Do not add in-app purchases, subscriptions, paid tiers, tip jars, purchase
  recovery, payment SDKs, or payment-dependent feature access.
- Do not add donation or tip buttons, checkout links, contribution prompts,
  embedded payment pages, or calls to contribute on the website.
- Ordinary privacy, terms, help, and product information links remain useful;
  their destinations must serve that purpose rather than redirect to checkout.
- Voluntary website support is separate from the app. It grants no features,
  content, credits, quota increases, or account privileges. Do not synchronize
  website payment status into the native account or analytics.
- PocketBase remains the only account and library backend. Existing analytics
  privacy, account isolation, and deletion requirements still apply.

## App Store release

- Verify that the app price is free and that the submitted build and metadata
  contain no purchase products, payment prompts, or paid-feature claims.
- Verify dependencies and the assembled binary contain no payment SDK.
- Privacy disclosures must describe actual shipped processing; remove planned
  purchase processing while retaining any applicable analytics disclosures.
- Review linked help and legal pages for incidental payment promotion before
  submission. Website support must remain independently discoverable.
- Earlier vendor test configuration is not evidence of a shipped purchase
  integration. Review existing Apple and vendor configuration separately;
  this source change does not delete vendor records, change agreements,
  alter banking or tax settings, or dispose of historical financial data.

## Policy basis

Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
sections 3.1.1 and 3.1.3 govern in-app purchases and external purchase prompts.
The website-only support model collects no payment through the app and does
not sell app access or content. Recheck current guidelines before submission
if the product or linked destinations change.

This is a product and release policy, not a determination of tax treatment or
App Review approval. Website support does not by itself resolve payment
recipient or tax reporting questions.
