module SessionTestHelper
  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[AUTH_COOKIE] = Current.session.id
      cookies[AUTH_COOKIE.to_s] = cookie_jar[AUTH_COOKIE]
    end
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete(AUTH_COOKIE.to_s)
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
