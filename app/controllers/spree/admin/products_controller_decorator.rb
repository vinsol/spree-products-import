Spree::Admin::ProductsController.class_eval do
  include Spree::Admin::ProductsController::CsvExport

  def index
    session[:return_to] = request.url
    respond_to do |format|
      format.html {}
      format.csv { send_data generate_product_csv, type: 'text/csv; charset=iso-8859-1; header=present',
        filename: "products_#{Time.current.to_i}.csv" }
    end
  end

  private
    def collection
      return @collection if @collection.present?
      params[:q] ||= {}
      params[:q][:deleted_at_null] ||= "1"

      params[:q][:s] ||= "name asc"
      @collection = super
      # Don't delete params[:q][:deleted_at_null] here because it is used in view to check the
      # checkbox for 'q[deleted_at_null]'. This also messed with pagination when deleted_at_null is checked.
      if params[:q][:deleted_at_null] == '0' && !request.format.csv?
        @collection = @collection.with_deleted
      end
      # @search needs to be defined as this is passed to search_form_for
      # Temporarily remove params[:q][:deleted_at_null] from params[:q] to ransack products.
      # This is to include all products and not just deleted products.
      @search = @collection.ransack(params[:q].reject { |k, _v| k.to_s == 'deleted_at_null' })
      @collection = @search.result.distinct_by_product_ids(params[:q][:s]).includes(product_includes)

      unless request.format.csv?
        @collection = @collection.page(params[:page]).per(params[:per_page] || Spree::Config[:admin_products_per_page])
      end
      @collection
    end
end
