module Spree #:nodoc:
  class Gateway::Qualpay < Gateway
      preference :merchantid, :string
      preference :security_key, :string
      LIVE_URL = 'https://api.qualpay.com/pg/sale'
      TEST_URL = 'https://api-test.qualpay.com/pg/sale'

      def initialize(options = {})
        requires!(options, :merchantid, :security_key)
        super
      end

      def provider_class
        Spree::Gateway::Qualpay
      end

      def payment_source_class
        Spree::CreditCard
      end

      def method_type
        'qualpay'
      end

      def purchase(money, creditcard, options = {})
        post = {}
        add_response_type(post)
        add_customer_data(post, options)
        add_order_data(post, options)
        add_creditcard(post, creditcard)
        add_address(post, creditcard, options)
        add_customer_data(post, options)
        add_amount(post, money, options)
        commit(money, post)
      end

      def supports_scrubbing?
        true
      end

      def scrub(transcript)
        transcript.
            gsub(%r((Authorization: Basic )\w+), '\1[FILTERED]').
            gsub(%r((&?card_num=)[^&]*)i, '\1[FILTERED]').
            gsub(%r((&?card_ccv2=)[^&]*)i, '\1[FILTERED]')
      end

      private

      def add_response_type(post)
        post[:response_format] = "JSON"
      end

      def add_customer_data(post, options)
        post[:merchant_id] = self.preferences[:merchantid]
        post[:security_key] = self.preferences[:security_key]
      end

      def add_order_data(post, options)
        post[:purchase_id] = options[:order_id] || generate_unique_id
        post[:merch_ref_num] = "C17854 - Road Solutions Inc"
      end

      def add_address(post, creditcard, options)
        post[:avs_address] = options[:billing_address][:address1]
        post[:avs_zip] = options[:billing_address][:zip]
      end

      def add_creditcard(post, creditcard)
        post[:card_number] = creditcard.number
        post[:exp_date] = "#{sprintf("%02d", creditcard.month)}#{"#{creditcard.year}"[-2, 2]}"
        post[:cvv2] = creditcard.verification_value
      end

      def add_amount(post, money, options)
        post[:amt_tran] = money
        post[:amt_tax] = options[:tax]
      end

      def parse(body)
        JSON.parse(body)
      end

      def commit(money, parameters)
        if Rails.env == 'production'
          uri = URI.parse(LIVE_URL)
        else
          uri = URI.parse(TEST_URL)
        end

        request = Net::HTTP::Post.new(uri.request_uri, initheader = {'Content-Type' => 'application/json'})
        request.body = parameters.to_json
        response = Net::HTTP.start(uri.hostname,uri.port, :read_timeout => 20000,:use_ssl => true) { |http| http.request(request) }
        raw_response = response.body
        begin
          response = parse(raw_response)
        rescue JSON::ParserError
          response = json_error(raw_response)
        end
        ActiveMerchant::Billing::Response.new(success?(response),
                     response["rmsg"],
                     response,
                     :test => true,
                     :authorization => response["auth_code"])
      end

      def success?(response)
        (response["rcode"] == "000")
      end

      def post_data(parameters = {})
        parameters.collect { |key, value| "#{key}=#{CGI.escape(value.to_s)}" }.join("&")
      end

      def json_error(raw_response)
        msg = 'Invalid response received from the Qualpay API.  Please contact Qualpay support if you continue to receive this message.'
        msg += "  (The raw response returned by the API was #{raw_response.inspect})"
        {
            "message" => msg
        }
      end
    end
end
