require 'catarse_paypal_express/processors'

module CatarsePaypalExpress::Payment
  class PaypalExpressController < ApplicationController
    skip_before_filter :verify_authenticity_token, :only => [:notifications]
    skip_before_filter :detect_locale, :only => [:notifications]
    skip_before_filter :set_locale, :only => [:notifications]
    skip_before_filter :force_http

    before_filter :setup_gateway
    before_filter :redirect_if_not_sign_in, :only => :success
    before_filter :redirect_if_confirmed, only: :success

    SCOPE = "projects.backers.checkout"

    layout :false

    def review

    end

    def ipn
      backer = Backer.where(:payment_id => params['txn_id']).first
      if backer
        notification = backer.payment_notifications.new({
          extra_data: JSON.parse(params.to_json.force_encoding(params['charset']).encode('utf-8'))
        })
        notification.save!
        backer.update_attributes({
          :payment_service_fee => params['mc_fee'],
          :payer_email => params['payer_email']
        })
      end
      return render status: 200, nothing: true
    rescue Exception => e
      Raven.capture_message("Paypal Notification Error: #{e.inspect}", { parameters: params })
      return render status: 200, nothing: true
    end

    def notifications
      backer = Backer.find params[:id]
      response = @@gateway.details_for(backer.payment_token)
      if response.params['transaction_id'] == params['txn_id']
        build_notification(backer, response.params)
        render status: 200, nothing: true
      else
        render status: 404, nothing: true
      end
    rescue Exception => e
      Raven.capture_message("Paypal Notification Error: #{e.inspect}", { parameters: params })
      render status: 404, nothing: true
    end

    def pay
      backer = current_user.backs.find params[:id]
      begin
        response = @@gateway.setup_purchase(backer.price_in_cents, {
          ip: request.remote_ip,
          return_url: payment_success_paypal_express_url(id: backer.id),
          cancel_return_url: payment_cancel_paypal_express_url(id: backer.id),
          currency_code: 'USD',
          description: t('paypal_description', scope: SCOPE, :project_name => backer.project.name, :value => backer.display_value),
          notify_url: payment_notifications_paypal_express_url(id: backer.id)
        })

        backer.update_attribute :payment_method, 'PayPal'
        backer.update_attribute :payment_token, response.token

        build_notification(backer, response.params)

        redirect_to @@gateway.redirect_url_for(response.token)
      rescue Exception => e
        Raven.capture_message("Paypal Notification Error: #{e.inspect}", { parameters: params })
        Rails.logger.info "-----> #{e.inspect}"
        paypal_flash_error
        return redirect_to main_app.new_project_backer_path(backer.project)
      end
    end

    def success
      backer = current_user.backs.find params[:id]


      begin
        @@gateway.purchase(backer.price_in_cents, {
          ip: request.remote_ip,
          token: backer.payment_token,
          payer_id: params[:PayerID]
        })

        # we must get the deatils after the purchase in order to get the transaction_id
        details = @@gateway.details_for(backer.payment_token)

        build_notification(backer, details.params)

        if details.params['transaction_id']
          backer.update_attribute :payment_id, details.params['transaction_id']
        end

        paypal_flash_success
        redirect_to main_app.thank_you_project_backer_path(project_id: backer.project.id, id: backer.id)
      rescue Exception => e
        Raven.capture_message("Paypal Notification Error: #{e.inspect}", { parameters: params })
        Rails.logger.info "-----> #{e.inspect}"
        paypal_flash_error
        return redirect_to main_app.new_project_backer_path(backer.project)
      end
    end

    def cancel
      backer = current_user.backs.find params[:id]
      flash[:failure] = t('paypal_cancel', scope: SCOPE)
      redirect_to main_app.new_project_backer_path(backer.project)
    end

  private
    def redirect_if_not_sign_in
      unless user_signed_in?
        session[:return_to] = payment_success_paypal_express_path(id: params[:id])
        redirect_to main_app.login_path
        return
      end
    end

    def redirect_if_confirmed
      backer = current_user.backs.find params[:id]
      if !backer.nil? && backer.confirmed
        paypal_flash_success
        redirect_to main_app.thank_you_project_backer_path(project_id: backer.project.id, id: backer.id)
      end
    end

    def build_notification(backer, data)
      processor = CatarsePaypalExpress::Processors::Paypal.new
      processor.process!(backer, data)
    end

    def paypal_flash_error
      flash[:failure] = t('paypal_error', scope: SCOPE)
    end

    def paypal_flash_success
      flash[:success] = t('success', scope: SCOPE)
    end

    def setup_gateway
      if ::Configuration[:paypal_username] and ::Configuration[:paypal_password] and ::Configuration[:paypal_signature]
        @@gateway ||= ActiveMerchant::Billing::PaypalExpressGateway.new({
          :login => ::Configuration[:paypal_username],
          :password => ::Configuration[:paypal_password],
          :signature => ::Configuration[:paypal_signature]
        })
      else
        puts "[PayPal] An API Certificate or API Signature is required to make requests to PayPal"
      end
    end
  end
end
