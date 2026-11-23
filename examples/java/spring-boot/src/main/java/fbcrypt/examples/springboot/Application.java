package fbcrypt.examples.springboot;

import java.util.List;
import java.util.stream.IntStream;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Scenarios S1 and S8: Spring Boot connects to an encrypted database.
 *
 * The application code has nothing about the key. The key is a property of the data
 * source (see application.properties), and its value comes from the environment.
 */
@SpringBootApplication
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

    @Bean
    CommandLineRunner run(JdbcTemplate jdbc) {
        return args -> {
            String note = jdbc.queryForObject("select note from demo where id = 1", String.class);
            System.out.println("S1 Spring Boot, key from the environment: " + note);

            // Parallel queries take connections from the pool. Each connection of the pool has the key.
            List<String> answers = IntStream.range(0, 8).parallel()
                    .mapToObj(i -> jdbc.queryForObject("select note from demo where id = 1", String.class))
                    .toList();
            long correct = answers.stream().filter("Hello from crypt_red"::equals).count();
            System.out.println("Pool of Spring Boot: 8 queries, " + correct + " correct answers");
        };
    }
}
