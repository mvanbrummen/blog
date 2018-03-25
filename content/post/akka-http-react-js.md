+++
draft = true
date = "2018-03-22T18:57:42+10:00"
title = "Building and Deploying Akka HTTP with React JS"
menu = ""
featureimage = ""
categories = []
tags = ["akka", "scala", "akka http", "reactjs", "docker"]

+++

I recently worked on a side project using [Akka HTTP](https://doc.akka.io/docs/akka-http/current/) and [ReactJS](https://reactjs.org/) and thought it was about time to consolidate my experience into a blog post. What better way to demonstrate what I learned than with a contrived example! 

We will be building a simple web application that will display random movie spoilers for our users.  

Let's get started!

## The Backend

First we need to setup the Akka HTTP server which will act as the application backend and serve the static ReactJS frontend.

You can easily bootstrap a new Akka HTTP project by using SBT and the Akka HTTP Seed [Giter8 template](https://github.com/akka/akka-http-scala-seed.g8) and entering the relevant information when prompted. 

```bash
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

We are going to setup a dedicated module for the Scala backend so we will need to move the Scala source to a new folder and edit the `build.sbt` file to reflect the new project structure.

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

We'll start with a basic Akka Actor which will be responsible for getting the movie spoilers. We will store the data in-memory in a `List` but a real application would probably be querying a data store.

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

The receive method will pattern match against the `GetSpoiler` case object and send a random movie spoiler message back to the sender and simply log a message for any unknown message.

We will also define JSON marshalling for the `MovieSpoiler` case class with support from the [Spray JSON](https://github.com/spray/spray-json) library.

```
implicit val movieSpoilerFormat = jsonFormat2(MovieSpoiler)
``` 

In a main method we'll instantiate the actor system and actor materializer, define our routes and start our Http server.

```
    implicit val system = ActorSystem()
    implicit val materializer = ActorMaterializer()

    val movieSpoilers = system.actorOf(Props[SpoilerActor], "movieSpoilers")



``` 

Let's define a get route that will use the `?` operator to ask our actor for a `Future` of a `MovieSpoiler` and return the result to the client.

```
      path("spoiler") {
        get {
          implicit lazy val timeout = Timeout(5.seconds)

          val spoiler: Future[MovieSpoiler] = (movieSpoilers ? GetSpoiler).mapTo[MovieSpoiler]

          complete(spoiler)
        }
      }
```

Another route will be added to serve static content from the resources directory which will contain the resulting `build` folder from our frontend (which we will dive into later).

```scala
      get {
        pathEndOrSingleSlash {
          getFromResource("build/index.html")
        } ~ {
          getFromResourceDirectory("build")
        }
      }
```

We use the `pathEndOrSingleSlash` directive to render `index.html` when a user hits the root URL and the `getFromResourceDirectory` directive to serve the rest of our static content (css, javascript etc).

To start the Http server, we pass the routes and http interface to `bindAndHandle` and use `Await.result` to block on the resulting `Future`.

```
    val bindingFuture = Http().bindAndHandle(route, "0.0.0.0", 8080)

    println(s"Server online at http://localhost:8080/...")

    Await.result(system.whenTerminated, Duration.Inf)
```

You'll notice that the server is bound to `"0.0.0.0"` rather than `"localhost"`. You will get issues running in a Docker container if you bind the server to localhost but more on that later. 

Putting the Akka HTTP implementation together.


```
// imports

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
      get {
        pathEndOrSingleSlash {
          getFromResource("build/index.html")
        } ~ {
          getFromResourceDirectory("build")
        }
      } ~
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

```bash
$ sbt
> project backend
[info] Set current project to movie-spoiler-app ...
> run
[info] Running com.example.MovieSpoilerApp
Server online at http://localhost:8080/...
```

```bash
$ curl localhost:8080/spoiler
{
   "movieTitle":"Rocky II",
   "spoiler":"Rocky wins"
}
```

Awesome! I can already hear ['Gonna Fly Now'](https://www.youtube.com/watch?v=ioE_O7Lm0I4) playing in my head.


## The Frontend

Since I haven't attained my PhD in Webpack configuration, we'll use [create-react-app](https://github.com/facebook/create-react-app) to bootstrap the ReactJS project into a new folder named frontend.

```bash
$ npm install -g create-react-app
$ create-react-app frontend  
$ ls
backend         build.sbt       frontend        project         target
```

Starting up the app with `yarn start` should result in the familiar create-react-app frontend.

```bash
$ cd frontend
$ yarn start
Compiled successfully!

You can now view frontend in the browser.

  Local:            http://localhost:3000/
  On Your Network:  http://10.0.0.3:3000/

Note that the development build is not optimized.
To create a production build, use yarn build.
```

![create-react-app-default.png](/img/create-react-app-default.png)
 
We can now update the `yarn build` command to move the productionised build folder to the resources directory in the backend module.

```
// package.json
    "build": "react-scripts build && mv build ../backend/src/main/resources/",
```

Now let's edit `App.js` to render something more interesting.

We'll define our `App` component and initialise state for a movie title and some spoiler text.

```
import React, { Component } from 'react';

export default class App extends Component {

  constructor(props) {
    super(props);

    this.state = { movieTitle: '', spoiler: '' }
  }
  ...
```

Interactions to our backend will be defined in a `getSpoiler` function, which will update the state with the data retrieved from our Akka HTTP server using `fetch`.

```
  getSpoiler = () => {
    fetch('/spoiler')
      .then(res => res.json())
      .then(data => {
        this.setState({
          movieTitle: data.movieTitle,
          spoiler: data.spoiler
        });
      })
      .catch(e => {
        console.log('Error:' + e);
      })
  }
```

Finally, we will add the render method which will display a random movie spoiler when the user clicks the button. This is accomplished by binding the `getSpoiler` function to the `onClick` event of the button which will re-render the component when the state changes. 

```
  render() {
    return (
      <div>
        <header className="app-header">
          <h1 className="app-title">Movie Spoilers</h1>
        </header>
        <section className="app-body">
          <h1 className="title">
            {this.state.movieTitle}
          </h1>
          <p className="spoiler-text">
            {this.state.spoiler}
          </p>
          <input className="button" type="button" value="RANDOM SPOILER" onClick={this.getSpoiler} />
        </section>
      </div>
    );
  }
```

Putting our component together.

```
import React, { Component } from 'react';
import './App.css';

export default class App extends Component {

  constructor(props) {
    super(props);

    this.state = { movieTitle: '', spoiler: '' }
  }

  getSpoiler = () => {
    fetch('/spoiler')
      .then(res => res.json())
      .then(data => {
        this.setState({
          movieTitle: data.movieTitle,
          spoiler: data.spoiler
        });
      })
      .catch(e => {
        console.log('Error:' + e);
      })
  }

  render() {
    return (
      <div>
        <header className="app-header">
          <h1 className="app-title">Movie Spoilers</h1>
        </header>
        <section className="app-body">
          <h1 className="title">
            {this.state.movieTitle}
          </h1>
          <p className="spoiler-text">
            {this.state.spoiler}
          </p>
          <input className="button" type="button" value="RANDOM SPOILER" onClick={this.getSpoiler} />
        </section>
      </div>
    );
  }
}
```


At this point, the only way to test the app would be to build the frontend and re-compile/run the backend since we use a relative path in the `fetch` http request. We could update the request to call the URL of our backend server (i.e. `http://localhost:8080/spoiler`) but we would run into issues with CORS and besides, a relative path is what we want to use for production. So how can we resolve this issue? 

We can actually configure the Webpack development server to [proxy requests to our backend](https://www.fullstackreact.com/articles/using-create-react-app-with-a-server/). So our request to `localhost:3000` will get routed to `localhost:8080` and work as intended in development. 

Open up `package.json` and add the following line:

```  
  ...
  },
  "proxy": "http://localhost:8080" // proxy requests to our backend 
}
```


Make sure the backend has started and execute `yarn start` to see the application in action.


![movie-spoiler-app.gif](/img/movie-spoiler-app.gif)

Let's add some rudimentary styling in `App.css` to make it less fugly.

```
body {
  background: #22c1c3;  
  background: -webkit-linear-gradient(to right, #fdbb2d, #22c1c3);  
  background: linear-gradient(to right, #fdbb2d, #22c1c3); 
}

.app-header {
  background-color: #222;
  height: 80px;
  padding: 20px;
  color: white;
}

.button {
  font-size: 1.5rem;
  width: 250px;
  padding: 20px;
  background-color: transparent;
  border: solid white 2px;
  color: white;
  border-radius: 8px;
}

.title {
  color: white;
  font-size: 4rem;
  text-decoration: underline;
}

.spoiler-text {
  font-size: 3rem;
  color: #f5f5f5;
}

.app-body {
  text-align: center;
}

.app-title {
  font-size: 1.5em;
}

.app-intro {
  font-size: large;
}

```

![movie-spoiler-app-styled.gif](/img/movie-spoiler-app-styled.gif)

Hmmm... still pretty ugly but you get the point!

# Dockerising and Deploying

There is a plethora of deployment options we could consider for our app but I'm going to go with [Docker](https://www.docker.com/). This will provide a nice portable unit of deployment and provide a variety of deployment targets from which to choose from.

Let's Dockerise our majestic application!

First, make sure you have [docker installed](https://docs.docker.com/install/) on your computer, a [Docker hub](https://hub.docker.com/) account (or another Docker registry to push to) and authentication [setup on the CLI](https://docs.docker.com/reference/commandline/cli/#login). 

We'll be using the [sbt-native-packager](https://github.com/sbt/sbt-native-packager) SBT plugin to package the app which allows us to package our SBT project into various formats including Docker images.

Open up `project/plugins.sbt` and add the following line.

```scala
addSbtPlugin("com.typesafe.sbt" % "sbt-native-packager" % "1.3.3")
```

In `build.sbt` we will make the following updates.

```scala
lazy val backend = project
  .enablePlugins(JavaAppPackaging) // required for docker packaging
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
    ),
    dockerRepository := Some("docker.io"), // docker hub
    dockerUsername := Some("mvanbrummen") // your docker hub username
  )
```

Make sure the frontend is built and then run the following.

```bash
$ sbt
> project backend
> compile
> docker:publishLocal
```

You should now see the new Docker image locally which you should be able to run as a container.

```bash
$ docker images
REPOSITORY                                                        TAG                 IMAGE ID            CREATED             SIZE
mvanbrummen/movie-spoiler-app                                     0.1-SNAPSHOT        8c1ad98dc77e        26 seconds ago      759MB
$ docker run -p 8080:8080 -it -d 8c1ad98dc77e
$ curl localhost:8080
{
  movieTitle: "The Sixth Sense",
  spoiler: "Bruce Willis was dead the whole time"
}

```

Now run the publish task to push the image to the Docker registry.

```bash
$ sbt
> project backend
> docker:publish
```

We can now run our container in AWS, Google Cloud, Docker Cloud etc. but I'll be deploying to [Hyper.sh](https://www.hyper.sh/) as it provides direct container hosting, saves us from having to worry about host/cluster resources and they have a 2 month free trial period.

Sign up to Hyper and follow the [getting started guide](https://docs.hyper.sh/GettingStarted/index.html) to setup the `hyper` CLI.

Now run the following commands (with your docker username substituted).

```
$ hyper pull mvanbrummen/movie-spoiler-app:0.1-SNAPSHOT
$ hyper run -d -p 80:8080 --name movie-spoiler-app mvanbrummen/movie-spoiler-app:0.1-SNAPSHOT
$ hyper fip allocate 1
$ hyper fip attach 209.177.87.17 movie-spoiler-app

```

As you can see the hyper CLI provides commands consistent with Docker. We just have to pull our image and run the container, exposing appliction port 8080 in the container to default port 80 on the host. Then if we want to route external traffic to app we just have to allocate an IP and attach it to our container. Navigate to the IP address and you should see your application in all its glory. 

You can take this even further by configurng for high availability/scalability, setting up a domain name, TLS, deployment pipleine etc. but I'll leave that as an exercise for the reader.

# Conclusion

We built a Scala/Akka HTTP backend API, hosted a static ReactJS frontend, Dockerised the application and deployed to a container hosting platform - all with relative ease. This example was quite trivial but hopefully you got something out of it and if anything, are inspired to go build something cool!    

Happy hacking!

*Full source code can be viewed [here](https://github.com/mvanbrummen/movie-spoiler-app).*

