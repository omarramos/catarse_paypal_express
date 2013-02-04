ActiveMerchant::Billing::PaypalExpressGateway.default_currency = 'USD'
ActiveMerchant::Billing::Base.mode = :test if (::Configuration[:paypal_test] == 'true')
