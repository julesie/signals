require "test_helper"

class LoadingSpinnerComponentTest < ViewComponent::TestCase
  test "renders spinner with default text" do
    render_inline(LoadingSpinnerComponent.new)
    assert_selector ".animate-spin"
    assert_text "Loading..."
  end

  test "renders spinner with custom text" do
    render_inline(LoadingSpinnerComponent.new(text: "Generating suggestion..."))
    assert_text "Generating suggestion..."
  end

  test "renders without text when nil" do
    render_inline(LoadingSpinnerComponent.new(text: nil))
    assert_selector ".animate-spin"
    assert_no_text "Loading"
  end
end
