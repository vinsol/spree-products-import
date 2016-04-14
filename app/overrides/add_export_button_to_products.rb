Deface::Override.new(
  virtual_path: 'spree/admin/products/index',
  name: 'add_export_button_to_products',
  # insert_before: "[data-hook='admin_products_sidebar']",
  insert_after: "erb[silent]:contains('content_for :page_actions do')",
  text: %Q{
    <%= button_link_to Spree.t(:export_csv), admin_products_url(params.except(:controller, :action).merge(format: :csv)), target: '_blank', class: 'btn btn-primary' %>
  }
)
