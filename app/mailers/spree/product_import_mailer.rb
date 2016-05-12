class Spree::ProductImportMailer < Spree::BaseMailer

  class NoMailToAddressesConfigured < Exception;  end

  def import_data_success_email(import_product_id, file_field)
    load_data_and_set_original_file_as_attachment(import_product_id, file_field)
    subject = "Data imported successfully"
    mail(to: to_address, from: from_address, subject: subject)
  end

  def import_data_failure_email(import_product_id, file_field, failed_csv)
    load_data_and_set_original_file_as_attachment(import_product_id, file_field)
    attachments['failed.csv'] = failed_csv
    subject = "Data import failed"
    mail(to: to_address, from: from_address, subject: subject)
  end

  def load_data_and_set_original_file_as_attachment(import_product_id, file_field)
    @import_product = Spree::ProductImport.find(import_product_id)
    original_file_name = @import_product.send("#{ file_field }_file_name")
    original_file_path = @import_product.send(file_field).path
    attachments[original_file_name] = File.read(original_file_path)
  end

  def to_address
    addresses = Spree::Config.import_mail_to_addresses.to_s.split(',').collect(&:strip)
    if addresses.empty?
      raise NoMailToAddressesConfigured
    else
      addresses
    end
  end

end
