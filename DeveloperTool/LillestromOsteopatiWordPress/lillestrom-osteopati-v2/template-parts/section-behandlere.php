<?php
/**
 * Template Part: Behandlere (Practitioners) Section
 *
 * Queries the 'behandler' Custom Post Type and outputs staff cards.
 *
 * @package Lillestrom_Osteopati
 * @since   1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$lo_behandlere_query = new WP_Query( array(
    'post_type'      => 'behandler',
    'posts_per_page' => -1,
    'orderby'        => 'menu_order',
    'order'          => 'ASC',
    'post_status'    => 'publish',
) );

if ( $lo_behandlere_query->have_posts() ) :
?>
<section class="section section-light" id="behandlere">
    <div class="container">
        <div class="section-header">
            <p class="section-label"><?php echo esc_html( lo_get_option( 'lo_behandlere_label', 'Behandlere' ) ); ?></p>
            <h2 class="section-title"><?php echo esc_html( lo_get_option( 'lo_behandlere_title', 'Møt våre behandlere' ) ); ?></h2>
        </div>
        <div class="staff-grid">
            <?php
            while ( $lo_behandlere_query->have_posts() ) :
                $lo_behandlere_query->the_post();

                $lo_behandler_title       = get_post_meta( get_the_ID(), '_behandler_title', true );
                $lo_behandler_education   = get_post_meta( get_the_ID(), '_behandler_education', true );
                $lo_behandler_specialties = get_post_meta( get_the_ID(), '_behandler_specialties', true );

                // Build the alt text.
                $lo_alt_text = get_the_title();
                if ( $lo_behandler_title ) {
                    $lo_alt_text .= ' – ' . $lo_behandler_title;
                }

                // Featured image or fallback.
                if ( has_post_thumbnail() ) {
                    $lo_photo_url = get_the_post_thumbnail_url( get_the_ID(), 'large' );
                } else {
                    $lo_photo_url = get_template_directory_uri() . '/assets/images/Behandling-T-10.jpg';
                }

                // Process content: convert to paragraphs and add staff-bio class.
                $lo_bio_content = get_the_content();
                $lo_bio_content = wpautop( $lo_bio_content );
                $lo_bio_content = str_replace( '<p>', '<p class="staff-bio">', $lo_bio_content );
            ?>
                <div class="staff-card">
                    <div class="staff-photo">
                        <img src="<?php echo esc_url( $lo_photo_url ); ?>" alt="<?php echo esc_attr( $lo_alt_text ); ?>">
                    </div>
                    <div class="staff-info">
                        <h3><?php the_title(); ?></h3>
                        <?php if ( $lo_behandler_title ) : ?>
                            <p class="staff-title"><?php echo esc_html( $lo_behandler_title ); ?></p>
                        <?php endif; ?>

                        <?php echo wp_kses_post( $lo_bio_content ); ?>

                        <div class="staff-details">
                            <?php if ( $lo_behandler_education ) : ?>
                                <div class="staff-detail-section">
                                    <h4><i class="fas fa-graduation-cap"></i> <?php echo esc_html( lo_get_option( 'lo_behandlere_education_heading', 'Utdanning' ) ); ?></h4>
                                    <ul>
                                        <?php
                                        $lo_education_lines = preg_split( '/\r\n|\r|\n/', trim( $lo_behandler_education ) );
                                        foreach ( $lo_education_lines as $lo_line ) :
                                            $lo_line = trim( $lo_line );
                                            if ( '' !== $lo_line ) :
                                        ?>
                                            <li><?php echo esc_html( $lo_line ); ?></li>
                                        <?php
                                            endif;
                                        endforeach;
                                        ?>
                                    </ul>
                                </div>
                            <?php endif; ?>

                            <?php if ( $lo_behandler_specialties ) : ?>
                                <div class="staff-detail-section">
                                    <h4><i class="fas fa-stethoscope"></i> <?php echo esc_html( lo_get_option( 'lo_behandlere_interests_heading', 'Faglige interesseområder' ) ); ?></h4>
                                    <ul>
                                        <?php
                                        $lo_specialty_lines = preg_split( '/\r\n|\r|\n/', trim( $lo_behandler_specialties ) );
                                        foreach ( $lo_specialty_lines as $lo_line ) :
                                            $lo_line = trim( $lo_line );
                                            if ( '' !== $lo_line ) :
                                        ?>
                                            <li><?php echo esc_html( $lo_line ); ?></li>
                                        <?php
                                            endif;
                                        endforeach;
                                        ?>
                                    </ul>
                                </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
            <?php endwhile; ?>
        </div>
    </div>
</section>
<?php
wp_reset_postdata();
endif;
