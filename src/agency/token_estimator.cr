module Agency
  class TokenEstimator
    def estimate(text : String) : Int32
      size = text.size
      return 0 if size == 0
      ((size.to_f / 4.0).ceil).to_i
    end
  end
end
