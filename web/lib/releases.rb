require 'pathname'

BUILDS = {
  'foreman-el' => 'Foreman on EL',
  'foreman-deb' => 'Foreman on Debian/Ubuntu',
  'katello' => 'Katello',
}.freeze

class ReleaseDataSource < ::Nanoc::DataSource
  identifier :releases

  def content_dir_name
    'guides'
  end

  def items
    require 'asciidoctor'
    require 'asciidoctor-tabs'

    result = []

    Pathname.new(content_dir_name).children.each do |child|
      # Legacy path
      legacy_child = child / 'guides'
      child = legacy_child if legacy_child.exist?

      index = child / 'index.adoc'
      unless index.exist?
        warn "Missing index.adoc; skipping #{child}"
        next
      end

      result << index_item(index)

      child.glob('doc-*/master.adoc').each do |path|
        result += guide_items(path)
      end
    end

    result
  end

  def item_changes
    changes_for_dir(content_dir_name)
  end

  def changes_for_dir(dir)
    # TODO: document.catalog[:includes] has the included filenames
    require 'listen'

    Nanoc::Core::ChangesStream.new do |cl|
      listener =
        Listen.to(dir) do |_modifieds, _addeds, _deleteds|
          cl.unknown
        end

      listener.start

      cl.to_stop { listener.stop }

      sleep
    end
  end

  private

  def index_item(path)
    attributes = {
      'attribute-missing' => 'error',
      'build' => 'foreman-el',
    }

    document = Asciidoctor.load_file(path.to_s, base_dir: path.dirname.to_s, attributes: attributes, safe: :safe)

    version = document.attributes['projectversion']

    new_item(
      document.render,
      {
        title: document.title,
        version: version,
        katello: document.attributes['katelloversion'],
        state: document.attributes.fetch('docstate', 'unsupported'),
      },
      "/#{version}/index.html",
    )
  end

  def guide_items(path)
    base_dir = path.dirname
    guide = base_dir.basename.to_s.delete_prefix('doc-')

    BUILDS.filter_map do |build, _title|
      attributes = {
        'attribute-missing' => 'error',
        'build' => build,
      }

      document = Asciidoctor.load_file(path, base_dir: base_dir, doctype: 'book', backend: 'html5', attributes: attributes, safe: :safe)

      next if document.catalog[:includes]['common/modules/snip_guide-not-ready']
      next if document.attributes.include?('hidefromnavigation')

      version = document.attributes['projectversion']

      context = {
        title: document.title,
        toc: document.converter.convert_outline(document),
        build: build,
        version: version,
      }

      new_item(
        document.render,
        context,
        "/#{version}/#{guide}/index-#{build}.html",
      )
    end
  end
end

def releases
  @items.find_all('/release/*/index.html')
end

def nav_versions
  releases.map do |release|
    builds = BUILDS.map do |build, title|
      guides = @items.find_all("/release/#{release[:version]}/*/index-#{build}.html").map do |guide|
        {
          title: guide[:title],
          path: guide.path,
        }
      end

      {
        'title': title,
        'guides': guides,
      }
    end

    {
      'foreman': release[:version],
      'katello': release[:katello],
      'state': release[:state],
      'title': "#{release[:title]} (#{release[:state]})",
      'builds': builds,
    }
  end
end

def releases_in_state(state)
  releases.filter { |release| release[:state] == state }
end
