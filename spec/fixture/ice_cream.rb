class Ingredience < Neo4j::Model
  property :name
end

class IceCream < Neo4j::Model
  property :flavour
  index :flavour
  has_n(:ingrediences).to(Ingredience)
  validates_presence_of :flavour
end
