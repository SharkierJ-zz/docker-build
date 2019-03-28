##
#Creats a git repository object, which has various git commands
# @param : Valid git repository ie git@github.com:<organization>/<repository>.git.
# @param : Name of the branch you would like to checkout on clone
# @param : Optional argument that the local path of the repository.
class GitRepository
  attr_reader :branch, :head, :name, :version

  def initialize(repository_name, branch='master', folder='')
    # Fetch the folder from the name, if it is not specified.
    if folder.empty?
      repository_folder = repository_name[repository_name.index('/')+1..repository_name.index('.git') - 1]
    else
      repository_folder = folder
    end

    # If the directory does not exist, assume that it has not been cloned.
    unless File.directory?(repository_folder)
      cmd = "git clone #{repository_name}"
      system(cmd, out: $stdout, err: :out)
      Dir.new(repository_folder)
    end
    Dir.chdir(repository_folder)

    @branch = branch # The branch that git repo will be on.
    @head = fetch_revision('HEAD') # The current head.
    @name = repository_name # The name of the repository.
   # @version = fetch_latest_tag # The last tagged version.
  end

  # Fetch the revision specified.
  # @param : Takes either HEAD or <tags> as string.
  # @returns : The revision number as a string.
  def fetch_revision(commit)
    `git rev-parse #{commit}`.tr("\n", '')
  end

  # Tags a git repository and and outputs to stdout.
  # @param : accepts valid tag arguments.
  # @returns standard out.
  def tag(arg='')
    `git tag #{arg} 2>&1`
  end

  # Does a 'git push'.
  # @param : accepts valid tag arguments.
  # @returns : standard out.
  def push(arg='')
    `git push #{arg} 2>&1`
  end

  # Fetches all the valid tags for repository branch.
  # Validates if the version name conforms to v*.*
  # @param : accepts valid tag arguments.
  def fetch_tags (arg)
    clean_tags = []
    tag(arg).split("\n").each { |vtag|
      clean_tags.push(vtag)}
    # contains tags that conform to format : discuss
    return clean_tags unless clean_tags.length < 1
    raise ImqsGitError, "no tags were found"
  end

  # Fetches the last version.
  def fetch_latest_tag(version_prefix = '')
    version_array = fetch_tags("-l \"#{version_prefix}*\"  --sort=-#{version_prefix}:refname")
    return version_array[0] unless version_array.length < 1
    # raise error if empty
    raise ImqsGitError, "No tags were found for prefix#{version_prefix}"
  end
end

# Custom error.
class ImqsGitError < StandardError
end
