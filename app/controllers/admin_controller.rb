# controllers/admin.rb:
# All admin controllers are dervied from this.
#
# Copyright (c) 2009 UK Citizens Online Democracy. All rights reserved.
# Email: hello@mysociety.org; WWW: http://www.mysociety.org/

class AdminController < ApplicationController
  layout "admin"
  before_action :authenticate

  # action to take if expecting an authenticity token and one isn't received
  def handle_unverified_request
    raise(ActionController::InvalidAuthenticityToken)
  end

  # For administration interface, return display name of authenticated user
  def admin_current_user
    if AlaveteliConfiguration.skip_admin_auth
      admin_http_auth_user
    else
      session[:admin_name]
    end
  end

  # If we're skipping Alaveteli admin authentication, assume that the environment
  # will give us an authenticated user name
  def admin_http_auth_user
    # This needs special magic in mongrel: http://www.ruby-forum.com/topic/83067
    # Hence the second clause which reads X-Forwarded-User header if available.
    # See the rewrite rules in conf/httpd.conf which set X-Forwarded-User
    if request.env["REMOTE_USER"]
      request.env["REMOTE_USER"]
    elsif request.env["HTTP_X_FORWARDED_USER"]
      request.env["HTTP_X_FORWARDED_USER"]
    else
      "*unknown*"
    end
  end

  def authenticate
    if AlaveteliConfiguration.skip_admin_auth
      session[:using_admin] = 1
      nil
    elsif session[:using_admin].nil? || session[:admin_name].nil?
      if params[:emergency].nil? || AlaveteliConfiguration.disable_emergency_user
        if !authenticated?
          ask_to_login(
            web: _('To log into the administrative interface'),
            email: _('Then you can log into the administrative interface'),
            email_subject: _('Log into the admin interface'),
            user_name: 'a superuser'
          )
        elsif !@user.nil? && @user.is_admin?
          session[:using_admin] = 1
          session[:admin_name] = @user.url_name
        else
          session[:using_admin] = nil
          session[:user_id] = nil
          session[:admin_name] = nil
          authenticate
        end
      else
        authenticate_or_request_with_http_basic do |user_name, password|
          if user_name == AlaveteliConfiguration.admin_username && password == AlaveteliConfiguration.admin_password
            session[:using_admin] = 1
            session[:admin_name] = user_name
          else
            request_http_basic_authentication
          end
        end
      end
    end
  end
end
