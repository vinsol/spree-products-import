class Spree::Admin::ProductImportsController < Spree::Admin::BaseController
  before_action :initialize_resource, only: [:new]
  before_action :load_resource, only: [:create]

  def new
  end

  def create
    if @product_import.save
      redirect_to admin_url, notice: Spree.t(:success, scope: [:admin, :product_import])
    else
      flash.now[:error] = Spree.t(:error, scope: [:admin, :product_import])
      render :new
    end
  end

  private
    def product_import_params
      params.permit(product_import: [:variants_csv, :products_csv])
    end

    def initialize_resource
      @product_import = Spree::ProductImport.new
    end

    def load_resource
      @product_import = Spree::ProductImport.new(product_import_params[:product_import])
    end

end
