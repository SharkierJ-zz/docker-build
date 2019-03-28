
class DockerBuild
  attr_reader  :service, :version

  def self.initialize
    @service = service
    @version = version
  end

  def self.build_image(service, version)
    cmd = "docker build -t #{service}:#{version} --build-arg netrc=\"$(cat ~/.netrc)\" --build-arg ssh_prv_key=\"$(cat ~/.ssh/id_rsa)\" --build-arg ssh_pub_key=\"$(cat ~/.ssh/id_rsa.pub)\" ."
    system(cmd)
  end
end

