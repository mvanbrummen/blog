+++
draft = true
date = "2018-03-22T18:57:42+10:00"
title = "Building and Deploying Akka Http with React JS"
menu = ""
featureimage = ""
categories = []
tags = ["akka", "scala", "akka http", "reactjs", "docker"]

+++

I recently worked on a side project using Akka Http and ReactJS and thought it was about time to consolidate my experience into a blog post. What better way to demonstrate this than with a contrived example! We will be building a simple web application that will display random movie spoilers for our users.  

Let's get started!

## The Backend

First we need to setup the Akka Http server which will act as the applications backend and serve the static ReactJS frontend.

You can easily bootstrap a new Akka Http project by using SBT and the Giter8 template and entering the relevant information when prompted. 

```
$ sbt -Dsbt.version=0.13.15 new https://github.com/akka/akka-http-scala-seed.g8

...

This is a seed project which creates a basic build for an Akka HTTP
application using Scala.

name [My Akka HTTP Project]: movie-spoiler-app
scala_version [2.12.4]:
akka_http_version [10.0.11]:
akka_version [2.5.11]:
organization [com.example]:
package [com.example]:

Template applied in ./movie-spoiler-app
```

We are going to setup a dedicated module for the Scala backend so we will need to move the Scala source to a new folder and edit the build.sbt file to reflect the new project structure.

```
$ cd ./movie-spoiler-app
$ mkdir backend
$ mv src/ backend/
``` 

```
// build.sbt
lazy val akkaHttpVersion = "10.0.11"
lazy val akkaVersion    = "2.5.11"

lazy val root = (project in file("."))
  .aggregate(backend)

lazy val backend = project
  .settings(
    inThisBuild(List(
      organization    := "com.example",
      scalaVersion    := "2.12.4"
    )),
    name := "movie-spoiler-app",
    libraryDependencies ++= Seq(
      "com.typesafe.akka" %% "akka-http"            % akkaHttpVersion,
      "com.typesafe.akka" %% "akka-http-spray-json" % akkaHttpVersion,
      "com.typesafe.akka" %% "akka-http-xml"        % akkaHttpVersion,
      "com.typesafe.akka" %% "akka-stream"          % akkaVersion,

      "com.typesafe.akka" %% "akka-http-testkit"    % akkaHttpVersion % Test,
      "com.typesafe.akka" %% "akka-testkit"         % akkaVersion     % Test,
      "com.typesafe.akka" %% "akka-stream-testkit"  % akkaVersion     % Test,
      "org.scalatest"     %% "scalatest"            % "3.0.1"         % Test
    )
  )


```

Now that the project is setup we can implement our backend server.

We'll start with a basic Akka Actor which will be responsible for getting the movie spoilers. We will store the data in-memory in a List but a real application would probably be querying a data store.

```
  case object GetSpoiler
  case class MovieSpoiler(movieTitle: String, spoiler: String)

  class SpoilerActor extends Actor with ActorLogging {

    val spoilers: List[MovieSpoiler] = List(
      MovieSpoiler("Harry Potter", "Dumbledore dies"),
      MovieSpoiler("Rocky II", "Rocky wins"),
      MovieSpoiler("The Sixth Sense", "Bruce Willis was dead the whole time")
    )

    def receive = {
      case GetSpoiler => sender ! Random.shuffle(spoilers).head
      case _ => log.info("Unknown message")
    }
  }

```

The receive method will pattern match against the GetSpoiler case object and send a random movie spoiler message back to the sender and log a message for an unknown message.

We will also define JSON marshalling for the MovieSpoiler class with support from the Spray JSON library.

```
implicit val movieSpoilerFormat = jsonFormat2(MovieSpoiler)
``` 

In a main method we'll instantiate the actor system and actor materializer, define our routes and start our Http server.

```
    implicit val system = ActorSystem()
    implicit val materializer = ActorMaterializer()

    val movieSpoilers = system.actorOf(Props[SpoilerActor], "movieSpoilers")



``` 
The get route will use the ask pattern to get a Future of a MovieSpoiler and complete and return the result to the client.

```
   val route =
      path("spoiler") {
        get {
          implicit lazy val timeout = Timeout(5.seconds)

          val spoiler: Future[MovieSpoiler] = (movieSpoilers ? GetSpoiler).mapTo[MovieSpoiler]

          complete(spoiler)
        }
      }

```
You'll notice that the server is bound to "0.0.0.0" rather than localhost. You will get issues running in a Docker container if you bind the server to localhost but more on that later. 

```
    val bindingFuture = Http().bindAndHandle(route, "0.0.0.0", 8080)

    println(s"Server online at http://localhost:8080/...")

    Await.result(system.whenTerminated, Duration.Inf)
```
Putting the Akka Http implementation together.


```
object MovieSpoilerApp {

  case object GetSpoiler

  case class MovieSpoiler(movieTitle: String, spoiler: String)

  class SpoilerActor extends Actor with ActorLogging {

    val spoilers: List[MovieSpoiler] = List(
      MovieSpoiler("Harry Potter", "Dumbledore dies"),
      MovieSpoiler("Rocky II", "Rocky wins"),
      MovieSpoiler("The Sixth Sense", "Bruce Willis was dead the whole time")
    )

    def receive = {
      case GetSpoiler => sender ! Random.shuffle(spoilers).head
      case _ => log.info("Unknown message")
    }
  }

  implicit val movieSpoilerFormat = jsonFormat2(MovieSpoiler)

  def main(args: Array[String]) {
    implicit val system = ActorSystem()
    implicit val materializer = ActorMaterializer()

    val movieSpoilers = system.actorOf(Props[SpoilerActor], "movieSpoilers")

    val route =
      path("spoiler") {
        get {
          implicit lazy val timeout = Timeout(5.seconds)

          val spoiler: Future[MovieSpoiler] = (movieSpoilers ? GetSpoiler).mapTo[MovieSpoiler]

          complete(spoiler)
        }
      }

    val bindingFuture = Http().bindAndHandle(route, "0.0.0.0", 8080)

    println(s"Server online at http://localhost:8080/...")

    Await.result(system.whenTerminated, Duration.Inf)
  }
}

```

To run it with SBT, just specify the module and execute the run task.

```
$ sbt
> project backend
[info] Set current project to movie-spoiler-app ...
> run
[info] Running com.example.MovieSpoilerApp
Server online at http://localhost:8080/...
```

```
$ curl localhost:8080/spoiler
{
   "movieTitle":"Rocky II",
   "spoiler":"Rocky wins"
}
```

Awesome! I can already hear 'Gonna Fly Now' playing in my head.


## The Frontend

Since I haven't attained my Phd in Webpack configuration, we'll be using create-react-app to bootstrap the ReactJS project into a new folder named frontend.

```
$ npm install -g create-react-app
$ create-react-app frontend  
```

Starting up the app with `yarn start` should result in the familiar create-react-app frontend.

We will be serving the frontend from the resources directory of the Akka Http backend so we can update the build to move the productionised build folder to the resource directory in the backend module.

```
// package.json
    "build": "react-scripts build && mv build/ ../backend/src/main/resources/",
```
