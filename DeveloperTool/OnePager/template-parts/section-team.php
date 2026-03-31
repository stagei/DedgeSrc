<?php
/**
 * Template Part: Team Members Section
 *
 * Queries the 'team_member' Custom Post Type and outputs staff cards.
 *
 * @package OnePager
 * @since   1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
    exit;
}

$op_team_query = new WP_Query( array(
    'post_type'      => 'team_member',
    'posts_per_page' => -1,
    'orderby'        => 'menu_order',
    'order'          => 'ASC',
    'post_status'    => 'publish',
) );

if ( $op_team_query->have_posts() ) :
?>
<section class="section section-light" id="team">
    <div class="container">
        <div class="section-header">
            <p class="section-label"><?php echo esc_html( op_get_option( 'op_team_label', 'Team' ) ); ?></p>
            <h2 class="section-title"><?php echo esc_html( op_get_option( 'op_team_title', 'Meet Our Team' ) ); ?></h2>
        </div>
        <div class="staff-grid">
            <?php
            while ( $op_team_query->have_posts() ) :
                $op_team_query->the_post();

                $op_member_title       = get_post_meta( get_the_ID(), '_team_member_title', true );
                $op_member_education   = get_post_meta( get_the_ID(), '_team_member_education', true );
                $op_member_specialties = get_post_meta( get_the_ID(), '_team_member_specialties', true );

                // Build the alt text.
                $op_alt_text = get_the_title();
                if ( $op_member_title ) {
                    $op_alt_text .= ' – ' . $op_member_title;
                }

                // Featured image or fallback.
                if ( has_post_thumbnail() ) {
                    $op_photo_url = get_the_post_thumbnail_url( get_the_ID(), 'large' );
                } else {
                    $op_photo_url = get_template_directory_uri() . '/assets/images/team-placeholder.jpg';
                }

                // Process content: convert to paragraphs and add staff-bio class.
                $op_bio_content = get_the_content();
                $op_bio_content = wpautop( $op_bio_content );
                $op_bio_content = str_replace( '<p>', '<p class="staff-bio">', $op_bio_content );
            ?>
                <div class="staff-card">
                    <div class="staff-photo">
                        <img src="<?php echo esc_url( $op_photo_url ); ?>" alt="<?php echo esc_attr( $op_alt_text ); ?>">
                    </div>
                    <div class="staff-info">
                        <h3><?php the_title(); ?></h3>
                        <?php if ( $op_member_title ) : ?>
                            <p class="staff-title"><?php echo esc_html( $op_member_title ); ?></p>
                        <?php endif; ?>

                        <?php echo wp_kses_post( $op_bio_content ); ?>

                        <div class="staff-details">
                            <?php if ( $op_member_education ) : ?>
                                <div class="staff-detail-section">
                                    <h4><i class="fas fa-graduation-cap"></i> <?php echo esc_html( op_get_option( 'op_team_education_heading', 'Education' ) ); ?></h4>
                                    <ul>
                                        <?php
                                        $op_education_lines = preg_split( '/\r\n|\r|\n/', trim( $op_member_education ) );
                                        foreach ( $op_education_lines as $op_line ) :
                                            $op_line = trim( $op_line );
                                            if ( '' !== $op_line ) :
                                        ?>
                                            <li><?php echo esc_html( $op_line ); ?></li>
                                        <?php
                                            endif;
                                        endforeach;
                                        ?>
                                    </ul>
                                </div>
                            <?php endif; ?>

                            <?php if ( $op_member_specialties ) : ?>
                                <div class="staff-detail-section">
                                    <h4><i class="fas fa-stethoscope"></i> <?php echo esc_html( op_get_option( 'op_team_interests_heading', 'Areas of Interest' ) ); ?></h4>
                                    <ul>
                                        <?php
                                        $op_specialty_lines = preg_split( '/\r\n|\r|\n/', trim( $op_member_specialties ) );
                                        foreach ( $op_specialty_lines as $op_line ) :
                                            $op_line = trim( $op_line );
                                            if ( '' !== $op_line ) :
                                        ?>
                                            <li><?php echo esc_html( $op_line ); ?></li>
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
