# frozen_string_literal: true

class CardComponentPreview < Lookbook::Preview
  # @label Default (with padding)
  def default
    render(CardComponent.new) do
      tag.div(class: "space-y-2") do
        safe_join([
          tag.p("Card Title", class: "text-lg font-semibold"),
          tag.p("Card content with default padding.", class: "text-zinc-400")
        ])
      end
    end
  end

  # @label Flush (no padding)
  def flush
    render(CardComponent.new(flush: true)) do
      tag.table(class: "min-w-full divide-y divide-zinc-700") do
        safe_join([
          tag.thead(class: "bg-zinc-700/50") do
            tag.tr do
              safe_join([
                tag.th("Name", class: "px-6 py-3 text-left text-xs font-medium text-zinc-400 uppercase"),
                tag.th("Value", class: "px-6 py-3 text-left text-xs font-medium text-zinc-400 uppercase")
              ])
            end
          end,
          tag.tbody(class: "divide-y divide-zinc-700") do
            tag.tr do
              safe_join([
                tag.td("Example", class: "px-6 py-4 text-sm"),
                tag.td("42", class: "px-6 py-4 text-sm text-zinc-400")
              ])
            end
          end
        ])
      end
    end
  end
end
