Deface::Override.new(
  virtual_path: 'spree/admin/general_settings/edit',
  name: 'add_admin_mail_to_address',
  insert_before: "#preferences fieldset .form-actions",
  text: %Q{
    <div class="row">
      <div class="col-md-6">
        <div class="form-group" data-hook="admin_general_setting_import_mail_to_address">
          <%= label_tag :import_mail_to_addresses %>
          <%= text_field_tag :import_mail_to_addresses, Spree::Config[:import_mail_to_addresses], placeholder: "add email addresses seperated by commas", class: 'form-control' %>
        </div>
      </div>
    </div>
  }
)
