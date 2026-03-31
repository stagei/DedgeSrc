<?php if (!defined('ABSPATH')) exit; ?>

<?php
$faq_query = new WP_Query(array(
    'post_type'      => 'faq_item',
    'posts_per_page' => -1,
    'orderby'        => 'menu_order',
    'order'          => 'ASC',
    'post_status'    => 'publish',
));

if ($faq_query->have_posts()) : ?>
<section class="section section-accent" id="faq">
    <div class="container">
        <div class="section-header">
            <p class="section-label"><?php echo esc_html( op_get_option( 'op_faq_label', 'FAQ' ) ); ?></p>
            <h2 class="section-title"><?php echo esc_html( op_get_option( 'op_faq_title', 'Frequently Asked Questions' ) ); ?></h2>
        </div>
        <div class="faq-list">
            <?php while ($faq_query->have_posts()) : $faq_query->the_post(); ?>
            <div class="faq-item">
                <button class="faq-question">
                    <span><?php echo esc_html(get_the_title()); ?></span>
                    <i class="fas fa-chevron-down faq-icon"></i>
                </button>
                <div class="faq-answer">
                    <?php echo wpautop(wp_kses_post(get_the_content())); ?>
                </div>
            </div>
            <?php endwhile; ?>
        </div>
    </div>
</section>
<?php
endif;
wp_reset_postdata();
?>
