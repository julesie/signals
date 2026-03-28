# frozen_string_literal: true

class PageLayoutComponentPreview < Lookbook::Preview
  # @label Default
  def default
    render(PageLayoutComponent.new) do
      tag.div(class: "space-y-4") do
        safe_join([
          tag.h1("Page Title", class: "text-2xl font-bold"),
          tag.p("This is an example page layout with default max-width.", class: "text-zinc-400")
        ])
      end
    end
  end

  # @label Narrow
  def narrow
    render(PageLayoutComponent.new(max_width: "max-w-md")) do
      tag.div(class: "space-y-4") do
        safe_join([
          tag.h1("Narrow Layout", class: "text-2xl font-bold"),
          tag.p("This is a narrow layout, useful for auth forms.", class: "text-zinc-400")
        ])
      end
    end
  end
end
