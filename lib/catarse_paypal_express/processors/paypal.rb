module CatarsePaypalExpress
  module Processors
    class Paypal

      def process!(backer, data)
        status = data["checkout_status"] || "pending"

        notification = backer.payment_notifications.new({
          extra_data: data
        })

        notification.save!

        backer.confirm! if success_payment?(status)
      rescue Exception => e
        Raven.capture_message("Paypal Notification Error: #{e.inspect}", { parameters: data })
      end

      protected

      def success_payment?(status)
        status == 'PaymentActionCompleted'
      end

    end
  end
end
