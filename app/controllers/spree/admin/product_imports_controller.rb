class Spree::Admin::ProductImportsController < Spree::Admin::BaseController

  def index
    @product_import = Spree::ProductImport.new
  end

  def create
    @product_import = Spree::ProductImport.new(product_import_params.merge(user_id: spree_current_user.id))
    if @product_import.save
      redirect_to admin_product_imports_url, notice: "Import process started successfully"
    else
      render :index
    end
  end

  private
    def product_import_params
      params.require(:product_import).permit(:products_csv)
    end
end
