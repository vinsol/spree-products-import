module Spree
  module Admin
    class ProductsController < ResourceController
      module CsvExport
        extend ActiveSupport::Concern

        def generate_product_csv
          CSV.generate do |csv|
            csv << csv_headers

            @collection.each do |product|
              csv << build_product_row(product)

              if product.has_variants?
                product.variants.each do |variant|
                  csv << build_variant_row(variant)
                end
              end
            end

            csv
          end
        end

        private
          def build_product_row(product)
            csv_headers.collect do |meth|
              if [:slug, :name, :price, :cost_price].include?(meth)
                product.send(meth)
              elsif meth == :description
                CGI::escapeHTML(product.description.to_s)
              elsif meth == :available_on
                product.available_on.try(:to_date)
              elsif meth == :option_types
                build_option_types_row(product)
              elsif meth == :properties
                build_properties_row(product)
              elsif meth == :taxons
                build_taxons_row(product)
              elsif meth == :shipping_category
                product.shipping_category.try(:name)
              elsif [:sku, :option_values, :stocks, :tax_category, :weight, :height, :width, :depth].include?(meth) && !product.has_variants?
                master = product.master
                if [:sku, :price, :cost_price].include?(meth)
                  master.send(meth)
                elsif meth == :tax_category
                  build_tax_category_row(master)
                elsif meth == :stocks
                  build_stocks_row(master)
                end
              end
            end
          end

          def build_variant_row(variant)
            csv_headers.collect do |meth|
              if [:sku, :price, :cost_price, :weight, :height, :width, :depth].include?(meth)
                variant.send(meth)
              elsif meth == :option_values
                build_option_values_row(variant)
              elsif meth == :tax_category
                build_tax_category_row(variant)
              elsif meth == :stocks
                build_stocks_row(variant)
              end
            end
          end

          def build_stocks_row(variant)
            # variant.stock_items.collect do |si|
            #   "#{si.stock_location.try(:admin_name)} -> #{si.count_on_hand}"
            # end.join(', ')
          end

          def build_tax_category_row(variant)
            variant.tax_category.try(:name)
          end

          def build_option_types_row(product)
            product.option_types.pluck(:name).join(', ')
          end

          def build_option_values_row(variant)
            variant.option_values.collect do |ov|
              "#{ov.option_type.name} -> #{ov.name}"
            end.join(', ')
          end

          def build_properties_row(product)
            product.product_properties.collect do |pp|
              "#{pp.property.try(:name)} -> #{pp.value}"
            end.join(', ')
          end

          def build_taxons_row(product)
            product.taxons.collect(&:pretty_name).join(', ')
          end

          def csv_headers
            @csv_headers ||= Spree::ProductImport::IMPORTABLE_PRODUCT_FIELDS.to_a
          end

      end
    end
  end
end