<?php
/**
 * Custom Post Types for the OnePager theme.
 *
 * Registers the "team_member" (Team Members), "faq_item" (FAQ),
 * and "service_type" (Services) custom post types, along with
 * meta boxes for team member details and service icons.
 *
 * @package OnePager
 * @since   1.0.0
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit; // Prevent direct access.
}

/* --------------------------------------------------------------------------
 * 1. Register Custom Post Types
 * ----------------------------------------------------------------------- */

add_action( 'init', 'op_register_post_types' );

/**
 * Register the Team Member, FAQ, and Service custom post types.
 */
function op_register_post_types() {

	/* ---- Team Member (Staff / Team) ---- */

	$team_member_labels = array(
		'name'                  => _x( 'Team Members', 'Post type general name', 'onepager' ),
		'singular_name'         => _x( 'Team Member', 'Post type singular name', 'onepager' ),
		'menu_name'             => _x( 'Team Members', 'Admin menu text', 'onepager' ),
		'name_admin_bar'        => _x( 'Team Member', 'Add New on Toolbar', 'onepager' ),
		'add_new'               => __( 'Add New', 'onepager' ),
		'add_new_item'          => __( 'Add New Team Member', 'onepager' ),
		'new_item'              => __( 'New Team Member', 'onepager' ),
		'edit_item'             => __( 'Edit Team Member', 'onepager' ),
		'view_item'             => __( 'View Team Member', 'onepager' ),
		'all_items'             => __( 'All Team Members', 'onepager' ),
		'search_items'          => __( 'Search Team Members', 'onepager' ),
		'not_found'             => __( 'No team members found.', 'onepager' ),
		'not_found_in_trash'    => __( 'No team members found in Trash.', 'onepager' ),
		'archives'              => __( 'Team Member Archives', 'onepager' ),
		'filter_items_list'     => __( 'Filter team members list', 'onepager' ),
		'items_list_navigation' => __( 'Team members list navigation', 'onepager' ),
		'items_list'            => __( 'Team members list', 'onepager' ),
	);

	$team_member_args = array(
		'labels'             => $team_member_labels,
		'public'             => true,
		'has_archive'        => false,
		'show_in_rest'       => true,
		'supports'           => array( 'title', 'editor', 'thumbnail', 'page-attributes' ),
		'menu_icon'          => 'dashicons-businessperson',
		'rewrite'            => array( 'slug' => 'team-member' ),
		'capability_type'    => 'post',
		'menu_position'      => 20,
		'show_in_menu'       => true,
		'show_ui'            => true,
		'show_in_admin_bar'  => true,
		'show_in_nav_menus'  => true,
		'can_export'         => true,
		'exclude_from_search'=> false,
		'publicly_queryable' => true,
	);

	register_post_type( 'team_member', $team_member_args );

	/* ---- FAQ Item ---- */

	$faq_labels = array(
		'name'                  => _x( 'FAQ', 'Post type general name', 'onepager' ),
		'singular_name'         => _x( 'FAQ', 'Post type singular name', 'onepager' ),
		'menu_name'             => _x( 'FAQ', 'Admin menu text', 'onepager' ),
		'name_admin_bar'        => _x( 'FAQ', 'Add New on Toolbar', 'onepager' ),
		'add_new'               => __( 'Add New', 'onepager' ),
		'add_new_item'          => __( 'Add New FAQ', 'onepager' ),
		'new_item'              => __( 'New FAQ', 'onepager' ),
		'edit_item'             => __( 'Edit FAQ', 'onepager' ),
		'view_item'             => __( 'View FAQ', 'onepager' ),
		'all_items'             => __( 'All FAQs', 'onepager' ),
		'search_items'          => __( 'Search FAQs', 'onepager' ),
		'not_found'             => __( 'No FAQs found.', 'onepager' ),
		'not_found_in_trash'    => __( 'No FAQs found in Trash.', 'onepager' ),
		'archives'              => __( 'FAQ Archives', 'onepager' ),
		'filter_items_list'     => __( 'Filter FAQ list', 'onepager' ),
		'items_list_navigation' => __( 'FAQ list navigation', 'onepager' ),
		'items_list'            => __( 'FAQ list', 'onepager' ),
	);

	$faq_args = array(
		'labels'             => $faq_labels,
		'public'             => true,
		'has_archive'        => false,
		'show_in_rest'       => true,
		'supports'           => array( 'title', 'editor', 'page-attributes' ),
		'menu_icon'          => 'dashicons-editor-help',
		'rewrite'            => array( 'slug' => 'faq' ),
		'capability_type'    => 'post',
		'menu_position'      => 21,
		'show_in_menu'       => true,
		'show_ui'            => true,
		'show_in_admin_bar'  => true,
		'show_in_nav_menus'  => true,
		'can_export'         => true,
		'exclude_from_search'=> false,
		'publicly_queryable' => true,
	);

	register_post_type( 'faq_item', $faq_args );

	/* ---- Service Type (Service Cards) ---- */

	register_post_type( 'service_type', array(
		'labels'             => array(
			'name'          => _x( 'Services', 'Post type general name', 'onepager' ),
			'singular_name' => _x( 'Service', 'Post type singular name', 'onepager' ),
			'menu_name'     => _x( 'Services', 'Admin menu text', 'onepager' ),
			'add_new'       => __( 'Add New', 'onepager' ),
			'add_new_item'  => __( 'Add New Service', 'onepager' ),
			'edit_item'     => __( 'Edit Service', 'onepager' ),
			'all_items'     => __( 'All Services', 'onepager' ),
			'not_found'     => __( 'No services found.', 'onepager' ),
		),
		'public'             => true,
		'has_archive'        => false,
		'show_in_rest'       => true,
		'supports'           => array( 'title', 'editor', 'page-attributes' ),
		'menu_icon'          => 'dashicons-heart',
		'rewrite'            => array( 'slug' => 'service-type' ),
		'capability_type'    => 'post',
		'menu_position'      => 22,
	) );
}

/* --------------------------------------------------------------------------
 * Service Type Meta Box (Icon)
 * ----------------------------------------------------------------------- */

add_action( 'add_meta_boxes', 'op_add_service_type_meta_boxes' );

function op_add_service_type_meta_boxes() {
	add_meta_box(
		'op_service_icon',
		__( 'Icon (Font Awesome)', 'onepager' ),
		'op_render_service_icon_meta_box',
		'service_type',
		'side',
		'default'
	);
}

function op_render_service_icon_meta_box( $post ) {
	wp_nonce_field( 'op_save_service_icon', 'op_service_icon_nonce' );
	$icon = get_post_meta( $post->ID, '_service_icon', true );
	$choices = function_exists( 'op_get_icon_choices' ) ? op_get_icon_choices() : array();
	?>
	<p>
		<select id="op_service_icon" name="_service_icon" class="large-text" style="width:100%">
			<?php foreach ( $choices as $value => $label ) : ?>
				<option value="<?php echo esc_attr( $value ); ?>" <?php selected( $icon, $value ); ?>>
					<?php echo esc_html( $label ); ?>
				</option>
			<?php endforeach; ?>
		</select>
	</p>
	<p class="description">
		<?php esc_html_e( 'Choose the icon displayed on the service card.', 'onepager' ); ?>
	</p>
	<?php
}

add_action( 'save_post_service_type', 'op_save_service_icon_meta', 10, 2 );

function op_save_service_icon_meta( $post_id, $post ) {
	if ( ! isset( $_POST['op_service_icon_nonce'] ) || ! wp_verify_nonce( $_POST['op_service_icon_nonce'], 'op_save_service_icon' ) ) {
		return;
	}
	if ( defined( 'DOING_AUTOSAVE' ) && DOING_AUTOSAVE ) {
		return;
	}
	if ( ! current_user_can( 'edit_post', $post_id ) ) {
		return;
	}
	if ( isset( $_POST['_service_icon'] ) ) {
		update_post_meta( $post_id, '_service_icon', sanitize_text_field( wp_unslash( $_POST['_service_icon'] ) ) );
	}
}


/* --------------------------------------------------------------------------
 * 2. Team Member Meta Box
 * ----------------------------------------------------------------------- */

add_action( 'add_meta_boxes', 'op_add_team_member_meta_boxes' );

/**
 * Register the "Team Member Details" meta box on the team member edit screen.
 */
function op_add_team_member_meta_boxes() {
	add_meta_box(
		'op_team_member_details',
		__( 'Team Member Details', 'onepager' ),
		'op_render_team_member_meta_box',
		'team_member',
		'normal',
		'high'
	);
}

/**
 * Render the Team Member meta box fields.
 *
 * @param WP_Post $post The current post object.
 */
function op_render_team_member_meta_box( $post ) {

	// Output a nonce field for verification on save.
	wp_nonce_field( 'op_save_team_member_meta', 'op_team_member_meta_nonce' );

	// Retrieve existing meta values (empty string as default).
	$title       = get_post_meta( $post->ID, '_team_member_title', true );
	$credentials = get_post_meta( $post->ID, '_team_member_credentials', true );
	$specialties = get_post_meta( $post->ID, '_team_member_specialties', true );

	?>
	<table class="form-table" role="presentation">

		<!-- Professional title -->
		<tr>
			<th scope="row">
				<label for="op_team_member_title">
					<?php esc_html_e( 'Title', 'onepager' ); ?>
				</label>
			</th>
			<td>
				<input
					type="text"
					id="op_team_member_title"
					name="_team_member_title"
					value="<?php echo esc_attr( $title ); ?>"
					class="large-text"
					placeholder="<?php esc_attr_e( 'e.g. Senior Consultant & Project Lead', 'onepager' ); ?>"
				/>
				<p class="description">
					<?php esc_html_e( 'Professional title displayed below the name.', 'onepager' ); ?>
				</p>
			</td>
		</tr>

		<!-- Credentials -->
		<tr>
			<th scope="row">
				<label for="op_team_member_credentials">
					<?php esc_html_e( 'Credentials', 'onepager' ); ?>
				</label>
			</th>
			<td>
				<textarea
					id="op_team_member_credentials"
					name="_team_member_credentials"
					rows="5"
					class="large-text"
					placeholder="<?php esc_attr_e( 'One credential per line', 'onepager' ); ?>"
				><?php echo esc_textarea( $credentials ); ?></textarea>
				<p class="description">
					<?php esc_html_e( 'Enter one credential per line.', 'onepager' ); ?>
				</p>
			</td>
		</tr>

		<!-- Specialties -->
		<tr>
			<th scope="row">
				<label for="op_team_member_specialties">
					<?php esc_html_e( 'Specialties', 'onepager' ); ?>
				</label>
			</th>
			<td>
				<textarea
					id="op_team_member_specialties"
					name="_team_member_specialties"
					rows="5"
					class="large-text"
					placeholder="<?php esc_attr_e( 'One specialty per line', 'onepager' ); ?>"
				><?php echo esc_textarea( $specialties ); ?></textarea>
				<p class="description">
					<?php esc_html_e( 'Enter one specialty per line.', 'onepager' ); ?>
				</p>
			</td>
		</tr>

	</table>
	<?php
}


/* --------------------------------------------------------------------------
 * 3. Save Team Member Meta
 * ----------------------------------------------------------------------- */

add_action( 'save_post_team_member', 'op_save_team_member_meta', 10, 2 );

/**
 * Persist the custom meta fields when a Team Member post is saved.
 *
 * Includes nonce verification, autosave check, and capability check.
 *
 * @param int     $post_id The post ID.
 * @param WP_Post $post    The post object.
 */
function op_save_team_member_meta( $post_id, $post ) {

	// 1. Verify the nonce.
	if (
		! isset( $_POST['op_team_member_meta_nonce'] ) ||
		! wp_verify_nonce( $_POST['op_team_member_meta_nonce'], 'op_save_team_member_meta' )
	) {
		return;
	}

	// 2. Bail on autosave — meta box fields are not submitted.
	if ( defined( 'DOING_AUTOSAVE' ) && DOING_AUTOSAVE ) {
		return;
	}

	// 3. Check that the current user has permission to edit the post.
	if ( ! current_user_can( 'edit_post', $post_id ) ) {
		return;
	}

	// 4. Define the fields to save and their sanitisation callbacks.
	$fields = array(
		'_team_member_title'       => 'sanitize_text_field',
		'_team_member_credentials' => 'sanitize_textarea_field',
		'_team_member_specialties' => 'sanitize_textarea_field',
	);

	foreach ( $fields as $meta_key => $sanitize_callback ) {
		if ( isset( $_POST[ $meta_key ] ) ) {
			$clean_value = call_user_func( $sanitize_callback, wp_unslash( $_POST[ $meta_key ] ) );
			update_post_meta( $post_id, $meta_key, $clean_value );
		} else {
			delete_post_meta( $post_id, $meta_key );
		}
	}
}
