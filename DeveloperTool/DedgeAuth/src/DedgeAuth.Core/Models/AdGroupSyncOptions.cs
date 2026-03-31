namespace DedgeAuth.Core.Models;

public class AdGroupSyncOptions
{
    public bool Enabled { get; set; } = true;
    public int SyncIntervalMinutes { get; set; } = 60;

    /// <summary>
    /// DNS suffix appended to tenant AdDomain to form LDAP path.
    /// E.g. AdDomain="DEDGE", LdapSuffix="fk.no" -> "LDAP://DEDGE.fk.no"
    /// </summary>
    public string LdapSuffix { get; set; } = "fk.no";

    /// <summary>
    /// LDAP filter for security groups. Default matches all ACL_ prefixed groups.
    /// </summary>
    public string GroupFilter { get; set; } = "(&(objectCategory=group)(objectClass=group)(cn=ACL_*))";
}
