require File.join(File.dirname(__FILE__), '..', 'spec_helper')

# Specs written by Nick Sieger and modified by Andreas Ronge

describe Neo4j::Model do

  describe "new" do
    before :each do
      @model = Neo4j::Model.new
    end
    subject { @model }

    it { should_not be_persisted }

    it "should allow access to properties before it is saved" do
      @model["fur"] = "none"
      @model["fur"].should == "none"
    end

    it "validation is performed when properties are changed" do
      v = IceCream.new
      v.should_not be_valid
      v.flavour = 'vanilla'
      v.should be_valid
    end

    it "validation is performed after save" do
      v = IceCream.new(:flavour => 'vanilla')
      v.save
      v.should be_valid
    end

    it "validation is skipped if save(:validate => false)" do
      v = IceCream.new(:name => 'illegal')
      v.save(:validate => false).should be_true
      v.should be_persisted
    end

    it "accepts a hash of properties which will be validated" do
      v = IceCream.new(:flavour => 'vanilla')
      v.should be_valid
    end


    it "save should create a new node" do
      v = IceCream.new(:flavour => 'q')
      v.save
      Neo4j::Node.should exist(v)
    end

    it "has nil as id befored saved" do
      v = IceCream.new(:flavour => 'andreas')
      v.id.should == nil
    end

  end

  describe "load" do
    it "should load a previously stored node" do
      model = Neo4j::Model.create
      result = Neo4j::Model.load(model.id)
      result.should == model
      result.should be_persisted
    end
  end


  describe "transaction" do
    it "runs a block in a transaction" do
      id = IceCream.transaction do
        a = IceCream.create :flavour => 'vanilla'
        a.ingrediences << Neo4j::Node.new
        a.id
      end
      IceCream.load(id).should_not be_nil
    end

    it "takes a 'tx' parameter that can be used to rollback the transaction" do
      id = IceCream.transaction do |tx|
        a = IceCream.create :flavour => 'vanilla'
        a.ingrediences << Neo4j::Node.new
        tx.fail
        a.id
      end
      IceCream.load(id).should be_nil
    end
  end

  describe "save" do
    it "stores a new model in the database" do
      model = IceCream.new
      model.flavour = "vanilla"
      model.save
      model.should be_persisted
      IceCream.load(model.id).should == model
    end

    it "stores a created and modified model in the database" do
      model = IceCream.new
      model.flavour = "vanilla"
      model.save
      model.should be_persisted
      IceCream.load(model.id).should == model
    end

    it "does not save the model if it is invalid" do
      model = IceCream.new
      model.save.should_not be_true
      model.should_not be_valid

      model.should_not be_persisted
      model.id.should be_nil
    end

    it "new_record? is false before saved and true after saved (if saved was successful)" do
      model = IceCream.new(:flavour => 'vanilla')
      model.should be_new_record
      model.save.should be_true
      model.should_not be_new_record
    end

    it "does not modify the attributes if validation fails when run in a transaction" do
      model = IceCream.create(:flavour => 'vanilla')

      IceCream.transaction do
      	model.flavour = "horse"
      	model.should be_valid
      	model.save

        model.flavour = nil
        model.flavour.should be_nil
        model.should_not be_valid
        model.save

        Neo4j::Rails::Transaction.fail
      end

      model.reload.flavour.should == 'vanilla'
    end

    it "create can initilize the object with a block" do
      model = IceCream.create! {|o| o.flavour = 'vanilla'}
      model.should be_persisted
      model.flavour = 'vanilla'

      model = IceCream.create {|o| o.flavour = 'vanilla'}
      model.should be_persisted
      model.flavour = 'vanilla'

    end
  end


  describe "error" do
    it "the validation method 'errors' returns the validation errors" do
      p = IceCream.new
      p.should_not be_valid
      p.errors.keys[0].should == :flavour
      p.flavour = 'vanilla'
      p.should be_valid
      p.errors.size.should == 0
    end
  end

  describe "ActiveModel::Dirty" do

    it "implements attribute_changed?, _change, _changed, _was, _changed? methods" do
      p = IceCream.new
      p.should_not be_changed
      p.flavour = 'kalle'
      p.should be_changed
      p.flavour_changed?.should == true
      p.flavour_change.should == [nil, 'kalle']
      p.flavour_was.should == nil
      p.flavour_changed?.should be_true
      p.flavour_was.should == nil

      p.flavour = 'andreas'
      p.flavour_change.should == ['kalle', 'andreas']
      p.save
      p.should_not be_changed
    end
  end

  describe "find" do
    it "should load all nodes of that type from the database" do
      model = IceCream.create :flavour => 'vanilla'
      IceCream.all.should include(model)
    end

    it "should find the node given it's id" do
      model = IceCream.create(:flavour => 'thing')
      IceCream.find(model.neo_id.to_s).should == model
    end


    it "should find a model by one of its attributes" do
      model = IceCream.create(:flavour => 'vanilla')
      IceCream.find("flavour: vanilla").should == model
    end

    it "should only find two by same attribute" do
      m1 = IceCream.create(:flavour => 'vanilla')
      m2 = IceCream.create(:flavour => 'vanilla')
      m3 = IceCream.create(:flavour => 'fish')
      IceCream.all("flavour: vanilla").size.should == 2
    end
  end

  describe "destroy" do
    before :each do
      @model = Neo4j::Model.create
    end

    it "should remove the model from the database" do
      id = @model.neo_id
      @model.destroy
      Neo4j::Node.load(id).should be_nil
    end
  end

  describe "create" do

    it "should save the model and return it" do
      model = Neo4j::Model.create
      model.should be_persisted
    end

    it "should accept attributes to be set" do
      model = Neo4j::Model.create :name => "Nick"
      model[:name].should == "Nick"
    end

    it "bang version should raise an exception if save returns false" do
      expect { IceCream.create! }.to raise_error(Neo4j::Model::RecordInvalidError)
    end

    it "bang version should NOT raise an exception" do
      icecream = IceCream.create! :flavour => 'vanilla'
      icecream.flavour.should == 'vanilla'
    end

    it "should run before and after create callbacks" do
      class RunBeforeAndAfterCreateCallbackModel < Neo4j::Rails::Model
        property :created
        before_create :timestamp

        def timestamp
          self.created = "yes"
          fail "Expected new record" unless new_record?
        end

        after_create :mark_saved
        attr_reader :saved

        def mark_saved
          @saved = true
        end
      end
      model = RunBeforeAndAfterCreateCallbackModel.create!
      model.created.should_not be_nil
      model.saved.should_not be_nil
    end

    it "should run before and after save callbacks" do
      class RunBeforeAndAfterSaveCallbackModel < Neo4j::Rails::Model
        property :created
        before_save :timestamp

        def timestamp
          self.created = "yes"
          fail "Expected new record" unless new_record?
        end

        after_save :mark_saved
        attr_reader :saved

        def mark_saved
          @saved = true
        end
      end

      model = RunBeforeAndAfterSaveCallbackModel.create!
      model.created.should_not be_nil
      model.saved.should_not be_nil
    end

    it "should run before and after new & save callbacks" do
      class RunBeforeAndAfterNewAndSaveCallbackModel < Neo4j::Rails::Model
        property :created
        before_save :timestamp

        def timestamp
          self.created = "yes"
          fail "Expected new record" unless new_record?
        end

        after_save :mark_saved
        attr_reader :saved

        def mark_saved
          @saved = true
        end
      end

      model = RunBeforeAndAfterNewAndSaveCallbackModel.new
      model.save
      model.created.should_not be_nil
      model.saved.should_not be_nil
    end

  end

  describe "update_attributes" do
    it "should save the attributes" do
      model = Neo4j::Model.new
      model.update_attributes(:a => 1, :b => 2).should be_true
      model[:a].should == 1
      model[:b].should == 2
    end

    it "should not update the model if it is invalid" do
      class UpdatedAttributesModel < Neo4j::Rails::Model
        property :name
        validates_presence_of :name
      end
      model = UpdatedAttributesModel.create!(:name => "vanilla")
      model.update_attributes(:name => nil).should be_false
      model.reload.name.should == "vanilla"
    end
  end

  describe "properties" do
    it "not required to run in a transaction (will create one)" do
      cream = IceCream.create :flavour => 'x'
      cream.flavour = 'vanilla'

      cream.flavour.should == 'vanilla'
      cream.should exist
    end

    it "should reuse the same transaction - not create a new one if one is already available" do
      cream = nil
      IceCream.transaction do
        cream = IceCream.create :flavour => 'x'
        cream.flavour = 'vanilla'
        cream.should exist

        # rollback the transaction
        Neo4j::Rails::Transaction.fail
      end

      cream.should_not exist
    end
  end

  describe "Neo4j::Rails::Validations::UniquenessValidator" do
    before(:all) do
      class ValidThing < Neo4j::Model
        index :email
        validates :email, :uniqueness => true
      end
      @klass = ValidThing
    end

    it "have correct kind" do
      Neo4j::Rails::Validations::UniquenessValidator.kind.should == :uniqueness
    end
    it "should not allow to create two nodes with unique fields" do
      a = @klass.create(:email => 'abc@se.com')
      b = @klass.new(:email => 'abc@se.com')

      b.save.should be_false
      b.errors.size.should == 1
    end

    it "should allow to create two nodes with not unique fields" do
      @klass.create(:email => 'abc@gmail.copm')
      b = @klass.new(:email => 'ab@gmail.com')

      b.save.should_not be_false
      b.errors.size.should == 0
    end

  end

  describe "attr_accessible" do
    before(:all) do
      @klass = create_model do
        attr_accessor :name, :credit_rating
        attr_protected :credit_rating
      end
    end

    it "given attributes are sanitized before assignment in method: attributes" do
      customer = @klass.new
      customer.attributes = {"name" => "David", "credit_rating" => "Excellent"}
      customer.name.should == 'David'
      customer.credit_rating.should be_nil

      customer.credit_rating= "Average"
      customer.credit_rating.should == 'Average'
    end

    it "given attributes are sanitized before assignment in method: new" do
      customer = @klass.new("name" => "David", "credit_rating" => "Excellent")
      customer.name.should == 'David'
      customer.credit_rating.should be_nil

      customer.credit_rating= "Average"
      customer.credit_rating.should == 'Average'
    end

    it "given attributes are sanitized before assignment in method: create" do
      customer = @klass.create("name" => "David", "credit_rating" => "Excellent")
      customer.name.should == 'David'
      customer.credit_rating.should be_nil

      customer.credit_rating= "Average"
      customer.credit_rating.should == 'Average'
    end

    it "given attributes are sanitized before assignment in method: update_attributes" do
      customer = @klass.new
      customer.update_attributes("name" => "David", "credit_rating" => "Excellent")
      customer.name.should == 'David'
      customer.credit_rating.should be_nil

      customer.credit_rating= "Average"
      customer.credit_rating.should == 'Average'
    end
  end

  describe "has_one, has_n, incoming" do
    before(:all) do
      item = create_model do
        property :name
        validates :name, :presence => true
        def to_s
          "Item #{name} class: #{self.class} id: #{self.object_id}"
        end
      end

      @order = create_model do
        property :name
        has_n(:items).to(item)
        validates :name, :presence => true
        def to_s
          "Order #{name} class: #{self.class} id: #{self.object_id}"
        end
      end

      @item = item # used as closure
      @item.has_n(:orders).from(@order, :items)
    end

    it "add nodes without save should only store it in memory" do
      order = @order.new :name => 'order'
      item =  @item.new :name => 'item'

      # then
      item.orders << order
      item.orders.should include(order)
      Neo4j.all_nodes.should_not include(item)
      Neo4j.all_nodes.should_not include(order)
    end

    it "add nodes with save should store it in db" do
      order = @order.new :name => 'order'
      item  = @item.new :name => 'item'

      # then
      item.orders << order
      item.orders.should include(order)
      item.save
      Neo4j.all_nodes.should include(item)
      Neo4j.all_nodes.should include(order)
      item.reload
      item.orders.should include(order)
    end
  end

  describe "i18n_scope" do
    subject { Neo4j::Rails::Model.i18n_scope }
    it { should == :neo4j }
  end
end
