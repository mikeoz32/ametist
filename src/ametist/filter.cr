module Ametist
  enum FilterOp
    Eq
    Ne
    Lt
    Lte
    Gt
    Gte
    In
    Contains
    StartsWith
    EndsWith
    Exists
  end

  alias FilterValue = String | Int32 | Float32 | Array(String) | Array(Int32) | Array(Float32)

  abstract class Filter
  end

  class FilterTerm < Filter
    getter field : String
    getter op : FilterOp
    getter value : FilterValue?

    def initialize(@field : String, @op : FilterOp, @value : FilterValue? = nil)
    end
  end

  class FilterAnd < Filter
    getter items : Array(Filter)

    def initialize(@items : Array(Filter))
    end
  end

  class FilterOr < Filter
    getter items : Array(Filter)

    def initialize(@items : Array(Filter))
    end
  end

  class FilterNot < Filter
    getter item : Filter

    def initialize(@item : Filter)
    end
  end
end
