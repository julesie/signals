require "test_helper"

class PlansTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "show displays plan content" do
    get plan_path
    assert_response :success
    assert_match plans(:with_content).content, response.body
  end

  test "show displays daily suggestion when present" do
    get plan_path
    assert_response :success
    assert_match plans(:with_content).daily_suggestion, response.body
  end

  test "edit renders form" do
    get edit_plan_path
    assert_response :success
    assert_select "textarea"
  end

  test "update saves plan content" do
    patch plan_path, params: {plan: {content: "New plan content"}}
    assert_redirected_to plan_path
    assert_equal "New plan content", @user.plan.reload.content
  end

  test "generate_suggestion calls service and redirects" do
    fake_response = Data.define(:content).new(content: "Go run today.")
    fake_chat = Object.new
    fake_chat.define_singleton_method(:with_params) { |**_| self }
    fake_chat.define_singleton_method(:with_instructions) { |_| self }
    fake_chat.define_singleton_method(:ask) { |_| fake_response }

    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }

    post generate_suggestion_plan_path
    assert_response :redirect
    assert_equal "Go run today.", @user.plan.reload.daily_suggestion
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end

  test "generate_suggestion shows error on failure" do
    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_| raise "API down" }

    post generate_suggestion_plan_path
    assert_response :redirect
    follow_redirect!
    assert_match "try again later", response.body
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end

  test "chat updates plan via LLM" do
    llm_response = "Updated plan\n---\nAdded rest days."
    fake_response = Data.define(:content).new(content: llm_response)
    fake_chat = Object.new
    fake_chat.define_singleton_method(:with_instructions) { |_| self }
    fake_chat.define_singleton_method(:ask) { |_| fake_response }

    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_| fake_chat }

    post chat_plan_path, params: {message: "Add rest days"}
    assert_redirected_to plan_path
    assert_equal "Updated plan", @user.plan.reload.content
  ensure
    RubyLLM.define_singleton_method(:chat, original_chat)
  end

  test "chat rejects blank message" do
    post chat_plan_path, params: {message: ""}
    assert_redirected_to plan_path
    follow_redirect!
    assert_match "enter a message", response.body
  end

  test "creates plan automatically if user has none" do
    Plan.where(user: @user).delete_all
    get plan_path
    assert_response :success
    assert_not_nil Plan.find_by(user: @user)
  end
end
