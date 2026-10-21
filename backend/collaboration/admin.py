from django.contrib import admin

from .models import (
    AuditEvent,
    Evidence,
    ExceptionCase,
    Invitation,
    LegacyInspection,
    Membership,
    ProductionJob,
    QualityInspection,
    Workspace,
)


@admin.register(Workspace)
class WorkspaceAdmin(admin.ModelAdmin):
    list_display = ("id", "name", "created_at")
    search_fields = ("name",)
    readonly_fields = ("created_at",)


@admin.register(Membership)
class MembershipAdmin(admin.ModelAdmin):
    list_display = ("workspace", "user", "role")
    list_filter = ("role",)
    search_fields = ("workspace__name", "user__username")


@admin.register(ProductionJob)
class ProductionJobAdmin(admin.ModelAdmin):
    list_display = ("part_name", "workspace", "printer", "quantity", "status", "updated_at")
    list_filter = ("status", "workspace")
    search_fields = ("part_name", "printer", "workspace__name")
    readonly_fields = ("id", "created_at", "updated_at")


for model in (Invitation, ExceptionCase, QualityInspection, Evidence, LegacyInspection, AuditEvent):
    admin.site.register(model)
