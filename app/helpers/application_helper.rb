module ApplicationHelper
  def sidebar_link(label, path, icon_path)
    active = current_page?(path)
    base   = "flex items-center gap-3 px-3 py-2 text-sm font-medium rounded-base"
    style  = active ? "text-fg-brand bg-brand-soft" : "text-body hover:text-heading hover:bg-neutral-secondary-soft"

    link_to path, class: "#{base} #{style}" do
      tag.svg(class: "w-5 h-5 shrink-0", fill: "none", viewBox: "0 0 24 24", stroke: "currentColor", "stroke-width": "1.5") do
        tag.path("stroke-linecap": "round", "stroke-linejoin": "round", d: icon_path)
      end + tag.span(label)
    end
  end
end
