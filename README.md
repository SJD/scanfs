scanfs
======

A ruby filesystem scanner that utilises threading to minimize IO wait. By design it will not cross filesystem boundaries. An in memory representation of the filesystem is built focused on directories, aggregating size, the number of files and directories, user sizes, max atime, and max mtime of everything below them. The raw stat structs for each directory are also kept.

A simple plugin framework allows the resultant structure to be handed to one or more processing classes post scan to do with what they will. You could store it, statistically analyse it, determine trends, graph it, whatever. This tool combined with some custom plugins can be very useful for reporting on, and managing, online and offline storage.

Particularly good when:

- using a Ruby implementation with good thread concurrency
- scanning large filesystems resident on appliances like NetApp or BlueArc filers
- you have cores and memory to burn, and lots of filesystems to get through
- you care about where data is, who owns it, and how commonly accessed or modified it is

Not particularly good when:

- using a Ruby implementation with poor thread concurrency
- scanning a filesystem that resides on a single disk
- you have one core and no memory

Can be very memory intensive depending on your filesystem density and/ or Ruby implementation of choice.

compatibilty
------------

The source is entirely core or stdlib. This won't run on ruby-1.8.x, however fixing it to do so probably wouldn't be too hard. It runs fine on ruby-1.9.x but won't fully realise the concurrency benefit. It works very well on jruby and works-ish on rubinius. I have no idea if it works on Mac OSX, and it won't work on  M$ Windows.

**jruby**: depending on your filesystem size, you may need to fiddle the heap allowances. I would typically run with the following - tested up to 9T - but of course it will depend on your filesystem density

    export JAVA_OPTS="-server -Xms512m -Xmx4096m"

**rubinius**: last time I checked 1.2.4 ran this fine. You probably want the 2.x series for concurrency however. I have managed to make it work reasonably reliably on _small_ filesystems with the JIT off.

    export RBXOPTS="-Xint" 

installation
------------

    gem build scanfs.gemspec
    gem install scanfs-x.x.x.gem

... where x.x.x is whatever version you happen to have.

executable
----------

The gem installs a single executable called scanfs which is theoretically in your path. Alternatively you can run it like so;

    ruby -Ilib bin/scanfs --help

When run with no arguments it will assume the current working directory much like ls. Without any plugins loaded, it will simply summarise and print basic information about the scan target.

common options
--------------

The most commonly used options are listed below;

- -t, --threads INTEGER Use this to set the number of worker threads. Currently the overall thread count will be this value + 1 + whatever threads your Ruby implementation spawns. The thread count setting can have a dramatic effect on the overall performance depending on many factors whether it be directory density, filer speed, file counts or number of available cores; so I play with this a lot. More is not _always_ better as thread contention or external factors can become an issue.

- -f, --filter FILTER1,FILTER2,FILTER3 ... If there are certain branches in your filesystem you don't want to look at (.snapshot for instance), then give a comma separated list with the filter option. It will discard any branches or leaves where an exact string match occurs.

- -p, --plugin PLUGIN1,PLUGIN2,PLUGIN3 ... Load and run the given plugins post scan. Currently each plugin (in specified order) will be handed a reference to the resultant data structure for processing. Generally speaking these would treat the structure as read only, however you may want to transform it for subsequent plugins.

The executable will also read and include any options you have in an environment variable named SCANFS_OPTS. This takes the same format as the command line itself, so you might have something like this;

  export SCANFS_OPTS="--threads 16 --filter .snapshot --plugin FilesystemFu"

plugins
-------

Plugins are a simple but central component of scanfs. This is typically where you would do all the useful stuff (unless you just wanted a quick overview of a filesystem). Plugins are really just Ruby classes that inherit the base plugin class from scanfs and are passed a handle to both the command line options, and the resultant data structure, post scan. Plugins can do whatever they want; put stuff in a database or nosql store, do some maths, or draw a pretty picture.

An example plugin;

    require 'scanfs'

    class FilesystemFu < ScanFS::Plugins::Base

      def self.author; "SJD"; end

      def self.version; "0.0.1"; end

      def self.description; "Super magic filesystem stuff"; end

      def run
        log.info { "#{self.class} inspecting options" }
        puts @opts.inspect
        log.info { "#{self.class} inspecting result" }
        puts @result.inspect
      end

    end # class FilesystemFu

The scanfs executable has a notion of a plugins directory. Dy default it will assume $HOME/.scanfs/plugins to be that location. You can change this with a command line option. It will attempt to load any .rb files it encounters there, and registers any plugins within those files. You could have as many plugins in one file as you want. When invoking a plugin from the command line, you would use class name; in the example plugin above this is FilesystemFu.

known issues
------------

- I don't really have any tests

todo
----

- Document plugins' expected usage of the ScanResult class
