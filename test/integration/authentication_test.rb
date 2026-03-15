require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "unauthenticated user is redirected to sign in" do
    get root_path
    assert_redirected_to new_user_session_path
  end

  test "authenticated user can access root" do
    user = User.create!(email: "test@example.com", password: "password123!")
    sign_in user
    get root_path
    assert_response :success
  end
end
