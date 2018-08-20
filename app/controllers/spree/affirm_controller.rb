module Spree
  class AffirmController < Spree::StoreController
    helper 'spree/orders'

    before_action :redirect_to_current_state, only: :confirm, if: -> { !params[:checkout_token] }
    before_action :redirect_to_completion, only: :confirm, if: -> { current_order.complete? }

    protect_from_forgery except: :confirm

    def confirm
      unless affirm_checkout.valid?
        affirm_checkout.errors.each do |field, error|
          case field
          when :billing_address
            phone = order.bill_address.phone
            order.bill_address = generate_spree_address(affirm_checkout.details['billing'])
            order.bill_address.phone = phone

          when :shipping_address
            phone = order.shipping_address.phone
            order.ship_address = generate_spree_address(affirm_checkout.details['shipping'])
            order.ship_address.phone = phone

          when :billing_email
            order.email = affirm_checkout.details["billing"]["email"]
          end
        end

        order.save
      end

      affirm_checkout.save

      create_affirm_payment

      while order.next; end

      if order.completed?
        session[:order_id] = nil
        flash.notice = Spree.t(:order_processed_successfully)
        flash['order_completed'] = true
        redirect_to completion_route
      else
        redirect_to checkout_state_path(order.state)
      end
    end

    def cancel
      redirect_to checkout_state_path(current_order.state)
    end

    private

    def redirect_to_current_state
      flash[:notice] = "Invalid order confirmation data."
      return redirect_to checkout_state_path(current_order.state)
    end

    def redirect_to_completion
      flash[:notice] = "Order already completed."
      return redirect_to completion_route
    end

    def affirm_checkout
      @affirm_checkout ||= Spree::AffirmCheckout.new(
        order: order,
        token: params[:checkout_token],
        payment_method: payment_method
      )
    end

    def payment_method
      @payment_method ||= Spree::PaymentMethod.find(params[:payment_method_id])
    end

    def order
      @order ||= current_order
    end

    def create_affirm_payment
      order.payments.create!({
        payment_method: payment_method,
        amount: order.total,
        source: affirm_checkout
      })
    end

    def find_country(address)
      country_code = address["address"]["country_code"]
      Spree::Country.find_by(iso3: country_code) || Spree::Country.find_by(iso: country_code)
    end

    def find_state(address)
      country = find_country(address)
      region_code = address["address"]["region1_code"]
      country.states.find_by(abbr: region_code) || country.states.find_by(name: region_code)
    end

    def get_names(address)
      name_parts = address["name"]["full"].split(" ")

      lastname  = address["name"]["last"] || name_parts.pop
      firstname = address["name"]["first"] || name_parts.join(" ")

      [firstname, lastname]
    end

    def generate_spree_address(address)
      country = find_country(address)
      state   = find_state(address)
      firstname, lastname = get_names(address)

      address = Spree::Address.create(
        city:       address["address"]["city"],
        phone:      address["phone_number"],
        zipcode:    address["address"]["postal_code"],
        address1:   address["address"]["street1"],
        address2:   address["address"]["street2"],
        state:      state,
        country:    country,
        lastname:   lastname,
        firstname:  firstname
      )

      address
    end
  end
end


