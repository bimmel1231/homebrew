module CompilerConstants
  GNU_GCC_VERSIONS = 3..9
  GNU_GCC_REGEXP = /^gcc-(4\.[3-9])$/
end

class CompilerFailure
  attr_reader :name
  attr_rw :cause, :version

  # Allows Apple compiler `fails_with` statements to keep using `build`
  # even though `build` and `version` are the same internally
  alias_method :build, :version

  def self.for_standard standard
    COLLECTIONS.fetch(standard) do
      raise ArgumentError, "\"#{standard}\" is not a recognized standard"
    end
  end

  def self.create(spec, &block)
    # Non-Apple compilers are in the format fails_with compiler => version
    if spec.is_a?(Hash)
      _, major_version = spec.each { |e| break e }
      name = "gcc-#{major_version}"
      # so fails_with :gcc => '4.8' simply marks all 4.8 releases incompatible
      version = "#{major_version}.999"
    else
      name = spec
      version = 9999
    end
    new(name, version, &block)
  end

  def initialize(name, version, &block)
    @name = name
    @version = version
    instance_eval(&block) if block_given?
  end

  def ===(compiler)
    name == compiler.name && version >= compiler.version
  end

  def inspect
    "#<#{self.class.name}: #{name} #{version}>"
  end

  MESSAGES = {
    :cxx11 => "This compiler does not support C++11"
  }

  cxx11 = proc { cause MESSAGES[:cxx11] }

  COLLECTIONS = {
    :cxx11 => [
      create(:gcc_4_0, &cxx11),
      create(:gcc, &cxx11),
      create(:llvm, &cxx11),
      create(:clang) { build 425; cause MESSAGES[:cxx11] },
      create(:gcc => "4.3", &cxx11),
      create(:gcc => "4.4", &cxx11),
      create(:gcc => "4.5", &cxx11),
      create(:gcc => "4.6", &cxx11),
    ],
    :openmp => [
      create(:clang) { cause "clang does not support OpenMP" },
    ]
  }
end

class CompilerSelector
  include CompilerConstants

  Compiler = Struct.new(:name, :version)

  COMPILER_PRIORITY = {
    :clang   => [:clang, :gcc, :llvm, :gnu, :gcc_4_0],
    :gcc     => [:gcc, :llvm, :gnu, :clang, :gcc_4_0],
    :llvm    => [:llvm, :gcc, :gnu, :clang, :gcc_4_0],
    :gcc_4_0 => [:gcc_4_0, :gcc, :llvm, :gnu, :clang],
  }

  def self.select_for(formula, compilers=self.compilers)
    new(formula, MacOS, compilers).compiler
  end

  def self.compilers
    COMPILER_PRIORITY.fetch(MacOS.default_compiler)
  end

  attr_reader :formula, :failures, :versions, :compilers

  def initialize(formula, versions, compilers)
    @formula = formula
    @failures = formula.compiler_failures
    @versions = versions
    @compilers = compilers
  end

  def compiler
    find_compiler { |c| return c.name unless fails_with?(c) }
    raise CompilerSelectionError.new(formula)
  end

  private

  def find_compiler
    compilers.each do |compiler|
      case compiler
      when :gnu
        GNU_GCC_VERSIONS.reverse_each do |v|
          name = "gcc-4.#{v}"
          version = compiler_version(name)
          yield Compiler.new(name, version) if version
        end
      else
        version = compiler_version(compiler)
        yield Compiler.new(compiler, version) if version
      end
    end
  end

  def fails_with?(compiler)
    failures.any? { |failure| failure === compiler }
  end

  def compiler_version(name)
    case name
    when GNU_GCC_REGEXP
      versions.non_apple_gcc_version(name)
    else
      versions.send("#{name}_build_version")
    end
  end
end
