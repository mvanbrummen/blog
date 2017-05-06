+++
draft = true
menu = ""
featureimage = ""
categories = []
tags = ["devops","gitlabci","testing"]
date = "2017-05-06T10:00:30+10:00"
title = "Setting Up Headless ChromeDriver for GitLab CI"

+++

For a new project at work I had the task of building a testing pipeline for a new selenium test suite. A majority of the existing builds for this project were in Bamboo but I wanted to leverage GitLabs CI/CD capabilites as the source code is hosted in an internal GitLab repository.   

## Getting Started

The first step was to put together a `gitlab-ci.yml` file in the root of the repository. 

```yml
image: maven:3.3.9-jdk-8

before_script:
  - apt-get update -qq & apt-get install wget
  - wget https://gist.githubusercontent.com/alonisser/11192482/raw/e1d8d4ed579d64902e951e4f9fa487b793035f9b/setup-headless-selenium-xvfb.sh
  - sh setup-headless-selenium-xvfb.sh
  - /sbin/start-stop-daemon --start --quiet --pidfile /tmp/custom_xvfb_1.pid --make-pidfile --background --exec /usr/bin/Xvfb -- :1 -ac -screen 0 1280x1024x16
  - export DISPLAY=:1
  - sleep 3

run_test:
  script:
    - mvn test 
```

The `setup-headless-selenium-xvfb.sh` script takes care of installing [xvfb](https://www.x.org/archive/X11R7.6/doc/man/man1/Xvfb.1.xhtml) and Google Chrome (along with all the dependencies required to run Chrome headless). This can be built into the Docker image to save having to do this everytime you run the pipeline.

Xvfb is started with the `start-stop-daemon` command (as you should not execute it directly due to the way it handles concurrent multiple instances) along with setting a display number as `:1` and a screen resolution. 

Finally the DISPLAY envrironment variable is exported and we sleep for 3 seconds to give xvfb time to start up.

## Preparing the  WebDriver

We now need to tell our webdriver to use our in-memory display server to render the browser in. For convenience I used the [web driver manager](https://github.com/bonigarcia/webdrivermanager) library which pulls the binaries from the internet which will now need to be further configured.   
To get the ChromeDriver binary installed I'll call 
`ChromeDriverManager.getInstance().setup();`

Then using `ChromeOptions` I will specify the `--no-sandbox` flag. This is necessary  within the Docker environment of GitLab CI otherwise you will get NoSuchSession exceptions.

```
ChromeOptions options = new ChromeOptions();
        options.addArguments("--no-sandbox");
```

Next step is to tell the chromedriver to use our in-memory display. Using the `ChromeDriverService` builder provides a convenient way to set the display. 
```
 ChromeDriverService service = new ChromeDriverService.Builder()
                .usingAnyFreePort()
                .withEnvironment(ImmutableMap.of("DISPLAY", ":1"))
                .usingDriverExecutable(new File(System.getenv("webdriver.chrome.driver")))
                .build();

        service.start();
```
Getting the path to the chromedriver binary can be found in the environment variable that was exported by the webdrivermanager.

## Putting It All Together

Adapting an example test case from the web driver manager project demonstrates the newly configured web driver in the context of an actual selenium test.

```
public class ChromeTest {

    private WebDriver driver;

    @BeforeClass
    public static void setupClass() {
        ChromeDriverManager.getInstance().setup();
    }

    @Before
    public void setupTest() throws Exception {
        ChromeOptions options = new ChromeOptions();
        options.addArguments("--no-sandbox");
            
        ChromeDriverService service = new ChromeDriverService.Builder()
                .usingAnyFreePort()
                .withEnvironment(ImmutableMap.of("DISPLAY", ":1"))
                .usingDriverExecutable(new File(System.getenv("webdriver.chrome.driver")))
                .build();

        service.start();
        driver = new ChromeDriver(service, options);
    }

    @After
    public void teardown() {
        if (driver != null) {
            driver.quit();
        }
    }

    @Test
    public void test() {
        // Your test code here. For example:
        WebDriverWait wait = new WebDriverWait(driver, 30); // 30 seconds of timeout
        driver.get("https://en.wikipedia.org/wiki/Main_Page"); // navigate to Wikipedia

        By searchInput = By.id("searchInput"); // search for "Software"
        wait.until(ExpectedConditions.presenceOfElementLocated(searchInput));
        driver.findElement(searchInput).sendKeys("Software");
        By searchButton = By.id("searchButton");
        wait.until(ExpectedConditions.elementToBeClickable(searchButton));
        driver.findElement(searchButton).click();

        wait.until(ExpectedConditions.textToBePresentInElementLocated(By.tagName("body"),
                "Computer software")); // assert that the resulting page contains a text
    }

}
```

## Conclusion

It's great to be able to execute selenium tests in a linux environment using in-memory displays but even better to execute them in a Docker environment such as GitLab CI. I'm really pleased with what I was able to put together and, even though there was a bit of upfront setup, I am looking forward to reaping the benefits of these automated tests going forward. Happy testing!   


