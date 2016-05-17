class Spree::Admin::ProductImportsController < Spree::Admin::BaseController
  before_action :load_resource, only: :create

  def new
    @product_import = Spree::ProductImport.new
  end

  def create
    if @product_import.save
      redirect_to new_admin_product_import_path, notice: Spree.t(:success, scope: [:admin, :product_import])
    else
      flash.now[:error] = Spree.t(:error, scope: [:admin, :product_import])
      render :new
    end
  end

  private
    def product_import_params
       product_import_params = params.require(:product_import).permit(:products_csv)
       product_import_params.merge(user_id: spree_current_user.id)
    end

    def load_resource
      @product_import = Spree::ProductImport.new(product_import_params)
    end

end
