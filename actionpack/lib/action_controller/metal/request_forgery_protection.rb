require 'active_support/core_ext/class/attribute'
require 'action_controller/metal/exceptions'

module ActionController #:nodoc:
  class InvalidAuthenticityToken < ActionControllerError #:nodoc:
  end

  # Controller actions are protected from Cross-Site Request Forgery (CSRF) attacks
  # by including a token in the rendered html for your application. This token is
  # stored as a random string in the session, to which an attacker does not have
  # access. When a request reaches your application, \Rails verifies the received
  # token with the token in the session. Only HTML and JavaScript requests are checked,
  # so this will not protect your XML API (presumably you'll have a different
  # authentication scheme there anyway). Also, GET requests are not protected as these
  # should be idempotent.
  #
  # CSRF protection is turned on with the <tt>protect_from_forgery</tt> method,
  # which checks the token and resets the session if it doesn't match what was expected.
  # A call to this method is generated for new \Rails applications by default.
  # You can customize the error message by editing public/422.html.
  #
  # The token parameter is named <tt>authenticity_token</tt> by default. The name and
  # value of this token must be added to every layout that renders forms by including
  # <tt>csrf_meta_tags</tt> in the html +head+.
  #
  # Learn more about CSRF attacks and securing your application in the
  # {Ruby on Rails Security Guide}[http://guides.rubyonrails.org/security.html].
  module RequestForgeryProtection
    extend ActiveSupport::Concern

    include AbstractController::Helpers
    include AbstractController::Callbacks

    CSRF_BYTES               = 32
    CSRF_SALT_BYTES          = 32
    HASHED_CSRF_TOKEN_DIGEST = Digest::SHA256
    HASHED_CSRF_TOKEN_BYTES  = 32
    MASKED_CSRF_TOKEN_BYTES  = CSRF_SALT_BYTES + HASHED_CSRF_TOKEN_BYTES
    ORIGIN_HEADER            = "HTTP_ORIGIN".freeze

    included do
      # Sets the token parameter name for RequestForgery. Calling +protect_from_forgery+
      # sets it to <tt>:authenticity_token</tt> by default.
      config_accessor :request_forgery_protection_token
      self.request_forgery_protection_token ||= :authenticity_token

      # Controls whether request forgery protection is turned on or not. Turned off by default only in test mode.
      config_accessor :allow_forgery_protection
      self.allow_forgery_protection = true if allow_forgery_protection.nil?

      helper_method :form_authenticity_token
      helper_method :protect_against_forgery?
      helper_method :csrf_token
    end

    module ClassMethods

      # Turn on request forgery protection. Bear in mind that only non-GET, HTML/JavaScript requests are checked.
      #
      # Example:
      #
      #   class FooController < ApplicationController
      #     protect_from_forgery :except => :index
      #
      # You can disable csrf protection on controller-by-controller basis:
      #
      #   skip_before_filter :verify_authenticity_token
      #
      # It can also be disabled for specific controller actions:
      #
      #   skip_before_filter :verify_authenticity_token, :except => [:create]
      #
      # Valid Options:
      #
      # * <tt>:only/:except</tt> - Passed to the <tt>before_filter</tt> call. Set which actions are verified.
      def protect_from_forgery(options = {})
        self.request_forgery_protection_token ||= :authenticity_token
        prepend_before_filter :verify_authenticity_token, options
      end
    end

    protected
      # The actual before_filter that is used. Modify this to change how you handle unverified requests.
      def verify_authenticity_token
        unless verified_request?
          logger.warn "WARNING: Can't verify CSRF token authenticity" if logger
          handle_unverified_request
        end
      end

      # This is the method that defines the application behavior when a request is found to be unverified.
      # By default, \Rails resets the session when it finds an unverified request.
      def handle_unverified_request
        reset_session
      end

      # Private: Checks if the the current request is verified to not be a cross-site
      # request. Verifies:
      #   * the format is restricted. By default, only HTML requests are checked.
      #   * it is a GET request? Gets should be safe and idempotent
      #   * the form_authenticity_token or X-CSRF-TOKEN header is a valid masked
      #     CSRF token
      #
      # Returns true or false if a request is verified.
      def verified_request?
        !protect_against_forgery? ||
          request.get?            ||
          (any_form_authenticity_token_valid? && same_origin_request?)
      end

      # Private: Test if any received token value is a valid masked token for the
      # current session.
      #
      # Returns true if any token is valid, otherwise false
      def any_form_authenticity_token_valid?
        token = form_authenticity_param
        return false unless token.present? && token.is_a?(String)
        masked_token_valid?(token)
      end

      # Private: Test if the passed token value is a valid masked token for the
      # current session.
      #
      # token - Base64 value to validate
      #
      # Returns true if token is valid, otherwise false
      def masked_token_valid?(token)
        # Decode received token as Base64. Set token to `nil` if input contains
        # invalid characters or has invalid padding
        token_bytes = begin
          Base64.strict_decode64(token)
        rescue ArgumentError
          nil
        end

        return false if token_bytes.blank? || token_bytes.length != MASKED_CSRF_TOKEN_BYTES

        # Separate decoded bytes into one time salt and hashed token
        salt = token_bytes.first(CSRF_SALT_BYTES)
        hashed_token = token_bytes.last(HASHED_CSRF_TOKEN_BYTES)

        # Generate the expected hashed token using the received one time salt and the
        # CSRF token from the session
        correct_hashed_token = HASHED_CSRF_TOKEN_DIGEST.digest(salt + csrf_token_bytes)

        # Validate the received hashed token matches the generated hashed token
        Rack::Utils.secure_compare(hashed_token, correct_hashed_token)
      end

      # Private: Generate masked token to be output in reponses. Each token
      # generated is unique and can be verified using the CSRF token from the
      # session and the one time salt embedded in the masked token.
      #
      # Returns Base64 encoded String of `SALT + DIGEST(SALT + CSRF_TOKEN)`.
      def form_authenticity_token
        salt = SecureRandom.random_bytes(CSRF_SALT_BYTES)
        masked_token = HASHED_CSRF_TOKEN_DIGEST.digest(salt + csrf_token_bytes)
        Base64.strict_encode64(salt + masked_token)
      end

      # Private: Decode the Base64 encoded CSRF token stored within the session
      # cookie.
      #
      # Returns String of CSRF token bytes.
      def csrf_token_bytes
        Base64.strict_decode64(csrf_token)
      end

      # Private: Retrieve the CSRF token value from the session cookie. If
      # there is no CSRF token within the session cookie, create a new random
      # token.
      #
      # Returns Base64 encoded String of CSRF token.
      def csrf_token
        session[:_csrf_token] ||= SecureRandom.base64(CSRF_BYTES)
      end

      # The form's authenticity parameter. Override to provide your own.
      def form_authenticity_param
        params[request_forgery_protection_token]
      end

      def protect_against_forgery?
        allow_forgery_protection
      end

      # Private: Checks if the request originated from github.com by looking at the
      # Origin header.
      #
      # Returns boolean.
      def same_origin_request?
        origin = request.env[ORIGIN_HEADER]

        # Some user agents don't send the Origin header.
        return true if origin.blank?

        origin == request.base_url
      end
  end
end
