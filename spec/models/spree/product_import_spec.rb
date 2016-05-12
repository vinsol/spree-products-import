require 'spec_helper'
require 'byebug'
require 'csv'

RSpec.describe Spree::ProductImport, type: :model do
  let(:product_import_without_csv) { build(:product_import) }
  let(:product_csv_file) { File.open(File.expand_path('../../../fixtures/products.csv', __FILE__)) }
  let(:variant_csv_file) { File.open(File.expand_path('../../../fixtures/variants.csv', __FILE__)) }
  let(:product_import) { build(:product_import, variants_csv: variant_csv_file, products_csv: product_csv_file) }
  before do
    Spree::Config[:import_mail_to_addresses] = "mail@spreeadmin.com"
    Spree::Store.current.mail_from_address = "spree@admin.com"
  end
  describe 'CONSTANTS' do
    ["IMPORTABLE_PRODUCT_FIELDS", "IMPORTABLE_VARIANT_FIELDS", "RELATED_PRODUCT_FIELDS", "RELATED_VARIANT_FIELDS", "IMAGE_EXTENSIONS", "OPTIONS_SEPERATOR"].each do |const_name|
      it "defines #{ const_name}" do
        expect(Spree::ProductImport.const_defined? const_name).to be(true)
      end
    end
  end

  describe 'validations' do
    context 'when no csv file provided' do
      it 'raises validation error' do
        expect(product_import_without_csv.valid?).to be(false)
        expect(product_import_without_csv.errors[:products_csv]).to eq(["can't be blank"])
        expect(product_import_without_csv.errors[:variants_csv]).to eq(["can't be blank"])
      end
    end
    context 'when atleast one csv provided' do
      it 'raises no validation error' do
        expect(product_import.valid?).to be(true)
      end
    end
  end

  describe 'import process' do
    before do
      product_import.save!
    end
    it "#start_product_import creates a delayed job for importing" do
      expect { product_import.send(:start_product_import) }.to change{ Delayed::Job.count }.by(1)
    end

    context 'When job is queued' do
      before do
        product_import.send(:start_product_import)
      end
      it 'worker loads the product data from csv files' do
        expect { Delayed::Worker.new.run(Delayed::Job.last) }.to change{ Spree::Product.count }.by(2)
      end
      it 'worker loads the variant data from csv files' do
        expect { Delayed::Worker.new.run(Delayed::Job.last) }.to change{ Spree::Variant.count }.by(3)
      end
    end

  end

end
