require 'csv'

class Spree::ProductImport < ActiveRecord::Base
  # ProductImport presumes that sku is a required field for variant

  #### Update ####
  # Export Product CSV from admin/product/index to update subsequent products/variants
  # Slug column is product's unique indentifier
  # Slug column should be present to update a product
  # Product row should be followed by respective variant rows
  # SKU column is variants unique identifier
  # Variant rows should have respective SKU's
  # Variant will be created if not found for respective SKU
  # Variant will be updated if found for respective SKU

  #### Create ####
  # Use exported Product CSV as sample csv to create products/variants
  # Slug column should be blank to create a product
  # Product row should be followed by respective variant rows
  # Slug is unique identifier of product
  # SKU is unique identifier of variant

  belongs_to :user

  # CONSTANTS
  IMPORTABLE_PRODUCT_FIELDS = [:slug, :sku, :name, :price, :cost_price, :available_on, :shipping_category, :tax_category,
                              :taxons, :option_types, :properties, :description, :option_values, :images, :stocks, :weight,
                              :height, :width, :depth].to_set
  IMPORTABLE_VARIANT_FIELDS = [:sku, :price, :cost_price, :tax_category, :option_values, :images, :stocks, :weight,
                              :height, :width, :depth].to_set

  RELATED_PRODUCT_FIELDS = [:taxons, :option_types, :option_values, :properties, :images, :stocks].to_set
  RELATED_VARIANT_FIELDS = [:option_values, :images, :stocks].to_set

  IMAGE_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.gif'].to_set
  OPTIONS_SEPERATOR = '->'

  has_attached_file :products_csv, validate_media_type: false

  # validations
  validates_attachment :products_csv, presence: true, content_type: { content_type: ["text/csv", "text/plain", 'application/vnd.ms-excel'] }
  validates :user, presence: true
  validates :products_csv, presence: true

  # callbacks
  after_commit :start_product_import

  private

    def start_product_import
      import_product_data
    end
    # handle_asynchronously :start_product_import

    def import_product_data
      @failed_import, @issues, @warnings, @headers, products_data_hash = [], [], [], [], {}
      row = 0
      CSV.foreach(products_csv.path, headers: true, header_converters: :symbol, encoding: 'ISO-8859-1') do |row_data|
        @headers = row_data.headers if @headers.blank?
        if product_row?(row_data)
          row += 1
          products_data_hash[row] = { product_data: row_data }
        else
          products_data_hash[row] ||= { product_data: {} }
          products_data_hash[row][:variants_data] ||= []
          products_data_hash[row][:variants_data] << row_data
        end
      end

      products_data_hash.each do |key, product_data_raw_hash|
        if product_data_raw_hash.present?
          @success, @issues = true, []
          product_data_hash = remove_blank_attributes(product_data_raw_hash)
          @success, @issues = import_product_from(product_data_hash)
          unless (@success && @issues.empty?)
            @failed_import << [product_data_raw_hash, @issues]
          end
        end
      end

      deliver_email
    end

    # CSV row is considered a product detail row if it contains Name OR Slug.
    def product_row?(product_data)
      product_data[:slug].present? || product_data[:name].present?
    end

    def deliver_email
      if @failed_import.empty?
        Spree::ProductImportMailer.import_data_success_email(id, "products_csv").deliver_later
      else
        failed_import_csv = build_csv_from_failed_import_list
        Spree::ProductImportMailer.import_data_failure_email(id, "products_csv", failed_import_csv).deliver_later
      end
    end

    def import_product_from(product_data_hash)
      product_data, variants_data = product_data_hash[:product_data], product_data_hash[:variants_data]

      if product_data.present?
        attribute_fields = build_data_hash(product_data, IMPORTABLE_PRODUCT_FIELDS, RELATED_PRODUCT_FIELDS)

        begin
          ActiveRecord::Base.transaction do
            product = find_or_build_product(attribute_fields)
            set_missing_product_options(product, product_data[:option_types]) if product_data[:option_types].present?
            set_missing_product_properties(product, product_data[:properties]) if product_data[:properties].present?
            add_taxons(product, product_data[:taxons]) if product_data[:taxons].present?
            if variants_data.blank?
              product.save!
              add_stocks(product, product_data[:stocks]) if product_data[:stocks].present?
            end
            add_images(product, product_data[:images]) if product_data[:images].present?

            if product.present? && variants_data.present?
              variants_data.each do |variant_data|
                attribute_fields = build_data_hash(variant_data, IMPORTABLE_VARIANT_FIELDS, RELATED_VARIANT_FIELDS)
                variant = find_or_build_variant(product, attribute_fields)
                set_variant_options(variant, variant_data[:option_values]) if variant_data[:option_values]
                variant.save!
                add_stocks(variant, variant_data[:stocks]) if variant_data[:stocks].present?
                add_images(variant, variant_data[:images]) if variant_data[:images].present?
              end
            end

            product.save!
          end
        rescue Exception => exception
          @issues << "ERROR: #{ exception.message }"
          return [false, @issues]
        end
      end
      [true, @issues]
    end

    def build_data_hash(data_row, attributes_to_read, related_attr)
      attribute_fields = {}
      copieable_attributes = attributes_to_read - related_attr

      data_row.each do |key, value|
        if copieable_attributes.include? key
          attribute_fields[key] = value.squish
        end
      end

      attribute_fields
    end

    def find_or_build_product(product_data)
      if product_data[:slug].present?
        raise 'Product not present for specified slug' if (product = Spree::Product.find_by('lower(slug) = ?', product_data[:slug].downcase)).blank?
      else
        product = Spree::Product.new
      end

      product_data[:description] = CGI.unescapeHTML(product_data[:description]) if product_data[:description].present?
      product_data[:tax_category] = get_tax_category(product_data[:tax_category]) if product_data[:tax_category].present?
      product_data[:shipping_category] = get_shipping_category(product_data[:shipping_category])

      product.assign_attributes(product_data)
      product
    end

    def find_or_build_variant(product, variant_data)
      raise 'SKU is required' if variant_data[:sku].blank?
      variant_data[:tax_category] = get_tax_category(variant_data[:tax_category]) if variant_data[:tax_category].present?
      variant = product.variants.find_by('lower(sku) = ?', variant_data[:sku].try(:downcase))
      variant ||= product.variants.build(sku: variant_data[:sku])
      variant.assign_attributes(variant_data)
      variant
    end

    def remove_blank_attributes(raw_hash)
      dup_hash = {}
      dup_hash[:product_data] = (raw_hash[:product_data].select { |k,v| k.present? && v.present? }.to_h)
      if raw_hash[:variants_data].present?
        dup_hash[:variants_data] = []
        raw_hash[:variants_data].each do |variant_data|
          dup_hash[:variants_data] << (variant_data.select { |k,v| k.present? && v.present? }.to_h)
        end
      end
      dup_hash
    end

    def set_variant_options(variant, option_values)
      product = variant.product
      option_values_provided = {}
      option_values.to_s.split(',').each do |option_pair|
        option_name, option_value = option_pair.split(OPTIONS_SEPERATOR).collect(&:squish)
        option_values_provided[option_name.downcase] = option_value
      end
      option_type_names = option_values_provided.keys.compact
      product.option_types.each do |option_type|
        option_name = option_type.name.try(:downcase)
        if option_type_names.include? option_name
          option_value_provided = option_values_provided[option_name]
          option_value = option_type.option_values.find_by('lower(name) = ?', option_value_provided.try(:downcase))
          option_value ||= option_type.option_values.build(name: option_value_provided)

          unless option_value.presentation
            option_value.presentation = option_value_provided
          end
          option_value.save!
          unless variant.option_values.include? option_value
            variant.option_values << option_value
          end
        else
          raise "Value for #{option_name} not provided"
        end
      end
    end

    def get_tax_category(tax_category_name)
      tax_category_name = tax_category_name.try(:squish)
      if tax_category_name.present?
        Spree::TaxCategory.find_by('lower(name) = ?', tax_category_name.downcase) || Spree::TaxCategory.create!(name: tax_category_name)
      else
        nil
      end
    end

    def get_shipping_category(shipping_category_name)
      shipping_category_name = shipping_category_name.try(:squish)
      if shipping_category_name.present?
        Spree::ShippingCategory.find_by('lower(name) = ?', shipping_category_name.downcase) || Spree::ShippingCategory.create!(name: shipping_category_name)
      else
        Spree::ShippingCategory.find_by('lower(name) = ?', 'default') || Spree::ShippingCategory.first
      end
    end

    def set_missing_product_options(product, option_types)
      option_types.to_s.split(',').each do |option|
        if (option_name = option.squish).present?
          option_type = Spree::OptionType.find_by('lower(name) = ?', option_name.try(:downcase))
          option_type ||= Spree::OptionType.new(name: option_name)
          option_type.presentation = option_name unless option_type.presentation
          option_type.save!
          unless product.option_types.include? option_type
            product.option_types << option_type
          end
        end
      end
    end

    def set_missing_product_properties(product, properties)
      properties.to_s.split(',').compact.each do |property_data|
        property_name, property_value = property_data.split(OPTIONS_SEPERATOR).collect(&:squish)
        if product_property = product.product_properties.joins(:property).find_by('lower(spree_properties.name) = ?', property_name.downcase)
          product_property.update_column(:value, property_value)
        elsif property = (Spree::Property.find_by('lower(name) = ?', property_name.downcase) || Spree::Property.create!(name: property_name, presentation: property_name.titleize))
          product.product_properties.build(property_id: property.id, value: property_value)
        end
      end
    end

    def get_taxon_from_chain(taxon_chain, parent=nil)
      if taxon_found = Spree::Taxon.find_by('lower(name) = ?', taxon_chain.shift.try(:downcase))
        if taxon_chain.length.zero?
          return taxon_found
        else
          return get_taxon_from_chain(taxon_chain, taxon_found)
        end
      else
        return nil
      end
    end

    def add_taxons(product, taxons)
      taxon_data = taxons.to_s.split(',')
      return if taxon_data.empty?
      taxon_data.each do |taxon|
        taxon_chain = taxon.split(OPTIONS_SEPERATOR).collect(&:squish)
        taxon_from_chain = get_taxon_from_chain(taxon_chain)
        if taxon_from_chain
          product.taxons << taxon_from_chain unless product.taxons.include? taxon_from_chain
        else
          @issues << "WARNING: Taxon - #{ taxon } not found"
        end
      end
    end

    def add_stocks(model_obj, stocks)
      variant = if model_obj.is_a?(Spree::Product)
        model_obj.master
      else
        model_obj
      end

      stocks_data = stocks.to_s.split(',')
      return if stocks_data.empty?
      stocks_data.each do |stock_data|

        if (stock = stock_data.split(OPTIONS_SEPERATOR).collect(&:squish)).blank?
          return
        elsif stock.length == 1
          stock_location = Spree::StockLocation.find_by(default: true)
          stock_count = stock[0]
        else
          stock_location = Spree::StockLocation.find_by('lower(admin_name) = ?', stock[0].downcase)
          stock_count = stock[1]
        end

        if stock_location.blank?
          raise 'Stock Location not found'
        end

        if stock_item = variant.stock_items.find_or_create_by!(stock_location: stock_location)
          stock_item.set_count_on_hand(stock_count)
        end
      end
    end

    def build_csv_from_failed_import_list
      column_names = @headers + [:issues]

      CSV.generate do |csv|
        csv << column_names
        @failed_import.each do |data_row|
          data_hash, issues = data_row[0], data_row[1]
          data = data_hash[:product_data].fields
          data << issues.join(', ')
          csv << data
          if data_hash[:variants_data].present?
            data_hash[:variants_data].each do |variant_data|
              csv << variant_data.fields
            end
          end
        end
      end
    end

    def add_images(model_obj, image_dir)
      return unless image_dir
      image_dir.squish!
      load_images(image_dir).each do |image_file|
        model_obj.images << Spree::Image.create(attachment: File.new("#{ image_dir }/#{ image_file }", 'r'))
      end
    end

    def load_images(image_dir)
      if Dir.exists?(image_dir)
        Dir.open(image_dir).entries.select do |entry|
          IMAGE_EXTENSIONS.include? File.extname(entry).try(:downcase)
        end
      else
        raise 'Image directory not found'
      end
    end

end
